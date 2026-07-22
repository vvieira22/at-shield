use crate::filter::NetworkFilter;
use crate::models::*;
use crate::store::Store;
use crate::{Command, Response, VERSION};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

/// If the UI stops pinging for this long during a session, tear protection down.
const UI_HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(12);

fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// `https://x.com/foo` → `x.com`
pub fn normalize_domain(raw: &str) -> String {
    let mut s = raw.trim().to_lowercase();
    if s.is_empty() {
        return s;
    }
    if let Some(rest) = s
        .strip_prefix("https://")
        .or_else(|| s.strip_prefix("http://"))
    {
        s = rest.to_string();
    }
    // drop path / query / fragment
    if let Some(i) = s.find('/') {
        s.truncate(i);
    }
    if let Some(i) = s.find('?') {
        s.truncate(i);
    }
    if let Some(i) = s.find('#') {
        s.truncate(i);
    }
    // userinfo@host
    if let Some(i) = s.rfind('@') {
        s = s[i + 1..].to_string();
    }
    // host:port
    if let Some((host, port)) = s.rsplit_once(':') {
        if port.chars().all(|c| c.is_ascii_digit()) {
            s = host.to_string();
        }
    }
    if let Some(rest) = s.strip_prefix("www.") {
        s = rest.to_string();
    }
    s.trim_end_matches('.').to_string()
}

/// Domains that are the same product (block/unblock together).
fn domain_aliases(domain: &str) -> &'static [&'static str] {
    match domain {
        "x.com" | "twitter.com" => &["x.com", "twitter.com"],
        _ => &[],
    }
}

struct LiveSession {
    profile_id: String,
    profile_name: String,
    state: SessionState,
    duration_secs: u64,
    /// Remaining when last ticked.
    remaining_secs: u64,
    tick_at: Instant,
    started_at: i64,
}

pub struct Engine {
    store: Store,
    filter: Arc<dyn NetworkFilter>,
    /// Hot path: id -> rule currently applied on the wire.
    active: Mutex<HashMap<String, SiteRule>>,
    session: Mutex<Option<LiveSession>>,
    /// Set when a session ends (manual or timer); Flutter pops it for the summary dialog.
    pending_summary: Mutex<Option<SessionRecord>>,
    /// Last time the desktop UI checked in (heartbeat / health / get_session).
    ui_heartbeat: Mutex<Option<Instant>>,
}

impl Engine {
    pub fn new(store: Store, filter: Arc<dyn NetworkFilter>) -> Result<Self, String> {
        store.seed_if_empty()?;
        Ok(Self {
            store,
            filter,
            active: Mutex::new(HashMap::new()),
            session: Mutex::new(None),
            pending_summary: Mutex::new(None),
            ui_heartbeat: Mutex::new(None),
        })
    }

    /// Background: if UI vanishes mid-session, clear hosts/WFP (no orphan blocks).
    pub fn spawn_ui_watchdog(self: &Arc<Self>) {
        let eng = Arc::clone(self);
        let _ = thread::Builder::new()
            .name("at-shield-ui-watchdog".into())
            .spawn(move || loop {
                thread::sleep(Duration::from_secs(1));
                eng.reap_if_ui_gone();
            });
    }

    fn touch_ui(&self) {
        *self.ui_heartbeat.lock() = Some(Instant::now());
    }

    fn reap_if_ui_gone(&self) {
        if self.session.lock().is_none() {
            return;
        }
        let Some(last) = *self.ui_heartbeat.lock() else {
            return;
        };
        if last.elapsed() <= UI_HEARTBEAT_TIMEOUT {
            return;
        }
        eprintln!(
            "[at-shield] UI sumiu (>{}s) — encerrando sessão e soltando rede",
            UI_HEARTBEAT_TIMEOUT.as_secs()
        );
        let _ = self.finish_session("ui_gone");
        let _ = self.pending_summary.lock().take();
    }

    /// Migrate + wipe leftover hosts. Blocks only start with a session.
    /// Call after IPC is listening so the UI can connect immediately.
    pub fn warm_protection(&self) -> Result<(), String> {
        self.migrate_bad_domains()?;
        let _ = self.store.purge_session_history_older_than(30 * 24 * 60 * 60);
        self.clear_network()
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        // Closing the service must never leave hosts/WFP armed.
        let _ = self.session.lock().take();
        let _ = self.clear_network();
    }
}

impl Engine {
    fn clear_network(&self) -> Result<(), String> {
        self.filter.clear_all().map_err(|e| e.to_string())?;
        self.active.lock().clear();
        Ok(())
    }

    fn reject_if_session(&self) -> Result<(), String> {
        if self.session.lock().is_some() {
            return Err("encerre a sessão pra editar sites".into());
        }
        Ok(())
    }

    /// Apply enabled sites for one profile (session start).
    fn apply_profile_network(&self, profile_id: &str) -> Result<Vec<SiteRule>, String> {
        let sites = self.store.list_sites(Some(profile_id))?;
        self.filter.clear_all().map_err(|e| e.to_string())?;
        let enabled: Vec<_> = sites.into_iter().filter(|s| s.enabled).collect();
        self.filter
            .apply_batch(&enabled)
            .map_err(|e| e.to_string())?;
        let mut active = self.active.lock();
        active.clear();
        for s in &enabled {
            active.insert(s.id.clone(), s.clone());
        }
        Ok(enabled)
    }

    /// Fix rows saved as full URLs before normalize existed.
    fn migrate_bad_domains(&self) -> Result<(), String> {
        let sites = self.store.list_sites(None)?;
        for mut site in sites {
            let n = normalize_domain(&site.domain);
            if n.is_empty() || n == site.domain {
                continue;
            }
            // if clean domain already exists in profile, drop the junk row
            let clash = self
                .store
                .list_sites(Some(&site.profile_id))?
                .into_iter()
                .any(|s| s.id != site.id && s.domain == n);
            if clash {
                let _ = self.filter.remove(&site);
                self.store.delete_site(&site.id)?;
                continue;
            }
            site.domain = n;
            self.store.upsert_site(&site)?;
        }
        Ok(())
    }

    pub fn filter_name(&self) -> &'static str {
        self.filter.name()
    }

    /// Flip alias rows in DB only (network applies on next session start).
    fn set_aliases_enabled(&self, site: &SiteRule) -> Result<(), String> {
        for &alias in domain_aliases(&site.domain) {
            if alias == site.domain {
                continue;
            }
            let Some(mut other) = self
                .store
                .list_sites(Some(&site.profile_id))?
                .into_iter()
                .find(|s| s.domain == alias)
            else {
                continue;
            };
            if other.enabled == site.enabled {
                continue;
            }
            other.enabled = site.enabled;
            self.store.upsert_site(&other)?;
        }
        Ok(())
    }

    fn delete_site_and_aliases(&self, id: &str) -> Result<(), String> {
        let Some(site) = self.store.get_site(id)? else {
            return Ok(());
        };
        let mut to_delete = vec![site.clone()];
        for &alias in domain_aliases(&site.domain) {
            if alias == site.domain {
                continue;
            }
            if let Some(other) = self
                .store
                .list_sites(Some(&site.profile_id))?
                .into_iter()
                .find(|s| s.domain == alias)
            {
                to_delete.push(other);
            }
        }
        for s in to_delete {
            self.store.delete_site(&s.id)?;
            self.active.lock().remove(&s.id);
        }
        Ok(())
    }

    fn refresh_session_clock(sess: &mut LiveSession) {
        if sess.state == SessionState::Running {
            let elapsed = sess.tick_at.elapsed().as_secs();
            if elapsed >= sess.remaining_secs {
                sess.remaining_secs = 0;
            } else {
                sess.remaining_secs -= elapsed;
            }
            sess.tick_at = Instant::now();
        }
    }

    /// End the live session, persist history, clear network. `reason`: `manual` | `timer`.
    fn finish_session(&self, reason: &str) -> Option<SessionRecord> {
        let sess = {
            let mut g = self.session.lock();
            let Some(mut sess) = g.take() else {
                return None;
            };
            Self::refresh_session_clock(&mut sess);
            sess
        };
        let _ = self.clear_network();
        let ended_at = now_unix();
        let elapsed_secs = (ended_at - sess.started_at).max(0) as u64;
        let attempts: Vec<DomainHit> = self
            .filter
            .drain_block_hits()
            .into_iter()
            .map(|(domain, count)| DomainHit { domain, count })
            .collect();
        let total_attempts = attempts.iter().map(|a| a.count).sum();
        let record = SessionRecord {
            id: Uuid::new_v4().to_string(),
            profile_id: sess.profile_id,
            profile_name: sess.profile_name,
            started_at: sess.started_at,
            ended_at,
            duration_secs: sess.duration_secs,
            elapsed_secs,
            ended_reason: reason.into(),
            total_attempts,
            attempts,
        };
        if let Err(e) = self.store.insert_session_record(&record) {
            eprintln!("[at-shield] save session history: {e}");
        }
        *self.pending_summary.lock() = Some(record.clone());
        Some(record)
    }

    fn snapshot_session(&self) -> Option<FocusSession> {
        {
            let mut g = self.session.lock();
            let Some(sess) = g.as_mut() else {
                return None;
            };
            Self::refresh_session_clock(sess);
            if sess.remaining_secs == 0 && sess.state == SessionState::Running {
                drop(g);
                self.finish_session("timer");
                return None;
            }
            Some(FocusSession {
                profile_id: sess.profile_id.clone(),
                profile_name: sess.profile_name.clone(),
                state: sess.state,
                remaining_secs: sess.remaining_secs,
                duration_secs: sess.duration_secs,
            })
        }
    }

    pub fn handle(&self, cmd: Command) -> Response {
        match self.handle_inner(cmd) {
            Ok(r) => r,
            Err(message) => Response::Error { message },
        }
    }

    fn handle_inner(&self, cmd: Command) -> Result<Response, String> {
        Ok(match cmd {
            Command::Health => {
                self.touch_ui();
                let enabled_sites = self
                    .store
                    .list_sites(None)?
                    .into_iter()
                    .filter(|s| s.enabled)
                    .count() as u32;
                let session_active = self.session.lock().is_some();
                Response::Pong {
                    version: VERSION.to_string(),
                    protection_active: !self.active.lock().is_empty() || session_active,
                    network_armed: self.filter.network_armed(),
                    session_active,
                    enabled_sites,
                }
            },
            Command::ListProfiles => Response::Profiles(self.store.list_profiles()?),
            Command::ListSites { profile_id } => {
                Response::Sites(self.store.list_sites(profile_id.as_deref())?)
            }
            Command::UpsertProfile { profile } => {
                self.reject_if_session()?;
                self.store.upsert_profile(&profile)?;
                Response::Profile(profile)
            }
            Command::DeleteProfile { id } => {
                self.reject_if_session()?;
                if Store::is_builtin_profile(&id) {
                    return Err("perfil padrão não pode ser excluído".into());
                }
                let profiles = self.store.list_profiles()?;
                if profiles.len() <= 1 {
                    return Err("precisa de pelo menos um perfil".into());
                }
                if !profiles.iter().any(|p| p.id == id) {
                    return Err(format!("perfil não encontrado: {id}"));
                }
                self.store.delete_profile(&id)?;
                Response::Empty
            }
            Command::UpsertSite { mut site } => {
                self.reject_if_session()?;
                let domain = normalize_domain(&site.domain);
                if domain.is_empty() || !domain.contains('.') {
                    return Err("domínio inválido — use algo como x.com".into());
                }
                site.domain = domain;
                // reuse existing row for same profile+domain (don't wipe settings on re-add)
                if let Some(existing) = self
                    .store
                    .list_sites(Some(&site.profile_id))?
                    .into_iter()
                    .find(|s| s.domain == site.domain)
                {
                    if site.id != existing.id {
                        site.id = existing.id;
                        site.include_subdomains = existing.include_subdomains;
                        site.redirect = existing.redirect;
                        site.page_file = existing.page_file;
                        site.http = existing.http;
                        site.https = existing.https;
                        // re-add = turn it back on
                        site.enabled = true;
                    }
                }
                self.store.upsert_site(&site)?;
                let _ = self.set_aliases_enabled(&site);
                Response::Site(site)
            }
            Command::DeleteSite { id } => {
                self.reject_if_session()?;
                self.delete_site_and_aliases(&id)?;
                Response::Empty
            }
            Command::SetEnabled { id, enabled } => {
                self.reject_if_session()?;
                let mut site = self
                    .store
                    .get_site(&id)?
                    .ok_or_else(|| format!("site not found: {id}"))?;
                site.enabled = enabled;
                self.store.upsert_site(&site)?;
                let _ = self.set_aliases_enabled(&site);
                Response::Site(
                    self.store
                        .get_site(&id)?
                        .unwrap_or(site),
                )
            }
            Command::SetEnabledBatch { ids, enabled } => {
                self.reject_if_session()?;
                // ponytail: one round-trip from UI; DB only — network on session start
                let mut changed = Vec::new();
                for id in &ids {
                    if let Some(mut site) = self.store.get_site(id)? {
                        site.enabled = enabled;
                        self.store.upsert_site(&site)?;
                        let _ = self.set_aliases_enabled(&site);
                        changed.push(site);
                    }
                }
                Response::Sites(changed)
            }
            Command::ApplyProfile { .. } => {
                // Blocks only via start_session.
                return Err("bloqueio só via sessão — use iniciar sessão".into());
            }
            Command::SetRedirectPage { id, page_file } => {
                self.reject_if_session()?;
                let mut site = self
                    .store
                    .get_site(&id)?
                    .ok_or_else(|| format!("site not found: {id}"))?;
                site.page_file = page_file;
                site.redirect = RedirectTarget::CustomPage;
                self.store.upsert_site(&site)?;
                Response::Site(site)
            }
            Command::StartSession {
                profile_id,
                duration_secs,
            } => {
                if self.session.lock().is_some() {
                    return Err("já tem sessão ativa — encerre antes".into());
                }
                let profiles = self.store.list_profiles()?;
                let profile = profiles
                    .into_iter()
                    .find(|p| p.id == profile_id)
                    .ok_or_else(|| format!("profile not found: {profile_id}"))?;
                // apply marked sites — don't abort session if WFP/hosts need Admin
                if let Err(e) = self.apply_profile_network(&profile_id) {
                    eprintln!("[at-shield] apply on session start: {e}");
                }
                self.filter.reset_block_hits();
                *self.pending_summary.lock() = None;
                self.touch_ui();
                *self.session.lock() = Some(LiveSession {
                    profile_id: profile.id.clone(),
                    profile_name: profile.name.clone(),
                    state: SessionState::Running,
                    duration_secs,
                    remaining_secs: duration_secs,
                    tick_at: Instant::now(),
                    started_at: now_unix(),
                });
                Response::Session(self.snapshot_session())
            }
            Command::EndSession => {
                let summary = self.finish_session("manual");
                // consume pending — Flutter already got the summary in this response
                let _ = self.pending_summary.lock().take();
                Response::SessionSummary(summary)
            }
            Command::GetSession => {
                self.touch_ui();
                Response::Session(self.snapshot_session())
            }
            Command::PopSessionSummary => {
                Response::SessionSummary(self.pending_summary.lock().take())
            }
            Command::ListSessionHistory => {
                Response::SessionHistory(self.store.list_session_history()?)
            }
            Command::ClearSessionHistory => {
                self.store.clear_session_history()?;
                Response::Empty
            }
            Command::UiHeartbeat => {
                self.touch_ui();
                Response::Empty
            }
        })
    }

    /// JSON in → JSON out (pipe / FFI).
    pub fn handle_json(&self, input: &str) -> String {
        let cmd: Result<Command, _> = serde_json::from_str(input);
        let resp = match cmd {
            Ok(c) => self.handle(c),
            Err(e) => Response::Error {
                message: format!("bad command: {e}"),
            },
        };
        serde_json::to_string(&resp).unwrap_or_else(|e| {
            format!(r#"{{"ok":"error","data":{{"message":"{e}"}}}}"#)
        })
    }
}

/// Tiny self-check: batch enable/disable must update filter without panicking.
#[cfg(test)]
mod tests {
    use super::*;
    use crate::NoopFilter;
    use std::sync::Arc;

    #[test]
    fn normalize_strips_url() {
        assert_eq!(normalize_domain("https://x.com/foo"), "x.com");
        assert_eq!(normalize_domain("HTTP://WWW.Twitter.com/"), "twitter.com");
        assert_eq!(normalize_domain("instagram.com"), "instagram.com");
    }

    #[test]
    fn twitter_alias_toggles_together() {
        let dir = std::env::temp_dir().join(format!("at-shield-alias-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter).unwrap();
        eng.warm_protection().unwrap();
        let sites = match eng.handle(Command::ListSites {
            profile_id: Some("profile-estudo".into()),
        }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        let tw = sites.iter().find(|s| s.domain == "twitter.com").unwrap();
        eng.handle(Command::SetEnabled {
            id: tw.id.clone(),
            enabled: false,
        });
        let sites = match eng.handle(Command::ListSites {
            profile_id: Some("profile-estudo".into()),
        }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        let tw = sites.iter().find(|s| s.domain == "twitter.com").unwrap();
        let x = sites.iter().find(|s| s.domain == "x.com").unwrap();
        assert!(!tw.enabled);
        assert!(!x.enabled);
        eng.handle(Command::DeleteSite { id: tw.id.clone() });
        let sites = match eng.handle(Command::ListSites {
            profile_id: Some("profile-estudo".into()),
        }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        assert!(sites.iter().all(|s| s.domain != "twitter.com" && s.domain != "x.com"));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn upsert_existing_domain_reenables() {
        let dir = std::env::temp_dir().join(format!("at-shield-upsert-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter).unwrap();
        eng.warm_protection().unwrap();
        let sites = match eng.handle(Command::ListSites {
            profile_id: Some("profile-estudo".into()),
        }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        let x = sites.iter().find(|s| s.domain == "x.com").unwrap();
        eng.handle(Command::SetEnabled {
            id: x.id.clone(),
            enabled: false,
        });
        let page = x.page_file.clone();
        eng.handle(Command::UpsertSite {
            site: SiteRule {
                id: "new-fake".into(),
                profile_id: "profile-estudo".into(),
                domain: "x.com".into(),
                include_subdomains: true,
                redirect: RedirectTarget::CustomPage,
                page_file: "foco.html".into(),
                http: false,
                https: true,
                enabled: true,
            },
        });
        let sites = match eng.handle(Command::ListSites {
            profile_id: Some("profile-estudo".into()),
        }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        let x = sites.iter().find(|s| s.domain == "x.com").unwrap();
        assert!(x.enabled);
        assert_eq!(x.page_file, page); // preserved, not wiped to foco.html
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn batch_toggle_is_db_only_until_session() {
        let dir = std::env::temp_dir().join(format!("at-shield-test-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter.clone()).unwrap();
        eng.warm_protection().unwrap();
        assert!(filter.applied.lock().is_empty());
        let sites = match eng.handle(Command::ListSites { profile_id: None }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        assert!(!sites.is_empty());
        let ids: Vec<_> = sites.iter().map(|s| s.id.clone()).collect();
        eng.handle(Command::SetEnabledBatch {
            ids: ids.clone(),
            enabled: true,
        });
        // marked in DB, but network idle until session
        assert!(filter.applied.lock().is_empty());
        eng.handle(Command::StartSession {
            profile_id: "profile-estudo".into(),
            duration_secs: 60,
        });
        assert!(!filter.applied.lock().is_empty());
        eng.handle(Command::EndSession);
        assert!(filter.applied.lock().is_empty());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn cannot_edit_sites_during_session() {
        let dir = std::env::temp_dir().join(format!("at-shield-lock-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter).unwrap();
        eng.warm_protection().unwrap();
        let sites = match eng.handle(Command::ListSites {
            profile_id: Some("profile-estudo".into()),
        }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        let id = sites[0].id.clone();
        eng.handle(Command::StartSession {
            profile_id: "profile-estudo".into(),
            duration_secs: 60,
        });
        match eng.handle(Command::SetEnabled {
            id: id.clone(),
            enabled: false,
        }) {
            Response::Error { message } => assert!(message.contains("sessão")),
            _ => panic!("expected reject during session"),
        }
        eng.handle(Command::EndSession);
        match eng.handle(Command::SetEnabled { id, enabled: false }) {
            Response::Site(_) => {}
            _ => panic!("expected ok after session end"),
        }
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn cannot_start_second_session() {
        let dir = std::env::temp_dir().join(format!("at-shield-2sess-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter).unwrap();
        eng.warm_protection().unwrap();
        eng.handle(Command::StartSession {
            profile_id: "profile-estudo".into(),
            duration_secs: 60,
        });
        match eng.handle(Command::StartSession {
            profile_id: "profile-adulto".into(),
            duration_secs: 60,
        }) {
            Response::Error { message } => assert!(message.contains("sessão")),
            other => panic!("expected reject, got {other:?}"),
        }
        eng.handle(Command::EndSession);
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn stale_ui_heartbeat_ends_session() {
        let dir = std::env::temp_dir().join(format!("at-shield-hb-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter).unwrap();
        eng.warm_protection().unwrap();
        eng.handle(Command::StartSession {
            profile_id: "profile-estudo".into(),
            duration_secs: 600,
        });
        assert!(eng.snapshot_session().is_some());
        *eng.ui_heartbeat.lock() = Some(Instant::now() - Duration::from_secs(30));
        eng.reap_if_ui_gone();
        assert!(eng.snapshot_session().is_none());
        match eng.handle(Command::PopSessionSummary) {
            Response::SessionSummary(None) => {}
            other => panic!("ui_gone should not leave summary dialog, got {other:?}"),
        }
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn end_session_saves_history() {
        let dir = std::env::temp_dir().join(format!("at-shield-hist-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter).unwrap();
        eng.warm_protection().unwrap();
        eng.handle(Command::StartSession {
            profile_id: "profile-estudo".into(),
            duration_secs: 120,
        });
        let summary = match eng.handle(Command::EndSession) {
            Response::SessionSummary(Some(r)) => r,
            other => panic!("expected summary, got {other:?}"),
        };
        assert_eq!(summary.profile_name, "Estudo");
        assert_eq!(summary.ended_reason, "manual");
        assert!(summary.ended_at >= summary.started_at);
        let hist = match eng.handle(Command::ListSessionHistory) {
            Response::SessionHistory(h) => h,
            _ => panic!("expected history"),
        };
        assert_eq!(hist.len(), 1);
        assert_eq!(hist[0].id, summary.id);
        // manual end consumes pending (UI got it in the response)
        match eng.handle(Command::PopSessionSummary) {
            Response::SessionSummary(None) => {}
            _ => panic!("expected empty pending after manual end"),
        }
        match eng.handle(Command::ClearSessionHistory) {
            Response::Empty => {}
            other => panic!("expected empty, got {other:?}"),
        }
        let hist = match eng.handle(Command::ListSessionHistory) {
            Response::SessionHistory(h) => h,
            _ => panic!("expected history"),
        };
        assert!(hist.is_empty());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn cannot_delete_builtin_profile() {
        let dir = std::env::temp_dir().join(format!("at-shield-builtin-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter).unwrap();
        eng.warm_protection().unwrap();
        match eng.handle(Command::DeleteProfile {
            id: "profile-estudo".into(),
        }) {
            Response::Error { message } => assert!(message.contains("padrão")),
            other => panic!("expected reject, got {other:?}"),
        }
        let profiles = match eng.handle(Command::ListProfiles) {
            Response::Profiles(p) => p,
            _ => panic!("expected profiles"),
        };
        assert!(profiles.iter().any(|p| p.id == "profile-estudo"));
        assert!(profiles.iter().any(|p| p.id == "profile-adulto"));
        let adulto = match eng.handle(Command::ListSites {
            profile_id: Some("profile-adulto".into()),
        }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        assert!(adulto.iter().any(|s| s.domain == "erome.com"));
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn history_older_than_30_days_is_purged() {
        let dir = std::env::temp_dir().join(format!("at-shield-purge-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let old = SessionRecord {
            id: "old".into(),
            profile_id: "p".into(),
            profile_name: "Old".into(),
            started_at: 1_000_000, // ancient
            ended_at: 1_000_100,
            duration_secs: 100,
            elapsed_secs: 100,
            ended_reason: "manual".into(),
            total_attempts: 0,
            attempts: vec![],
        };
        store.insert_session_record(&old).unwrap();
        assert_eq!(store.purge_session_history_older_than(30 * 24 * 60 * 60).unwrap(), 1);
        assert!(store.list_session_history().unwrap().is_empty());
        let _ = std::fs::remove_dir_all(dir);
    }
}
