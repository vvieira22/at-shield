use crate::filter::NetworkFilter;
use crate::models::*;
use crate::store::Store;
use crate::{Command, Response, VERSION};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

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
    /// Remaining when last (re)started or paused.
    remaining_secs: u64,
    tick_at: Instant,
}

pub struct Engine {
    store: Store,
    filter: Arc<dyn NetworkFilter>,
    /// Hot path: id -> rule currently applied on the wire.
    active: Mutex<HashMap<String, SiteRule>>,
    session: Mutex<Option<LiveSession>>,
}

impl Engine {
    pub fn new(store: Store, filter: Arc<dyn NetworkFilter>) -> Result<Self, String> {
        store.seed_if_empty()?;
        Ok(Self {
            store,
            filter,
            active: Mutex::new(HashMap::new()),
            session: Mutex::new(None),
        })
    }

    /// Apply enabled rules to the network adapter (can be slow: DNS + WFP).
    /// Call after IPC is listening so the UI can connect immediately.
    pub fn warm_protection(&self) -> Result<(), String> {
        self.migrate_bad_domains()?;
        self.reapply_enabled()
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

    fn reapply_enabled(&self) -> Result<(), String> {
        let sites = self.store.list_sites(None)?;
        let enabled: Vec<_> = sites.into_iter().filter(|s| s.enabled).collect();
        self.filter
            .clear_all()
            .map_err(|e| e.to_string())?;
        self.filter
            .apply_batch(&enabled)
            .map_err(|e| e.to_string())?;
        let mut active = self.active.lock();
        active.clear();
        for s in enabled {
            active.insert(s.id.clone(), s);
        }
        Ok(())
    }

    /// Flip alias rows in DB only — caller must `reapply_enabled` after.
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

    fn snapshot_session(&self) -> Option<FocusSession> {
        let mut g = self.session.lock();
        let Some(sess) = g.as_mut() else {
            return None;
        };
        Self::refresh_session_clock(sess);
        if sess.remaining_secs == 0 && sess.state == SessionState::Running {
            // auto-end
            *g = None;
            let _ = self.reapply_enabled();
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

    pub fn handle(&self, cmd: Command) -> Response {
        match self.handle_inner(cmd) {
            Ok(r) => r,
            Err(message) => Response::Error { message },
        }
    }

    fn handle_inner(&self, cmd: Command) -> Result<Response, String> {
        Ok(match cmd {
            Command::Health => Response::Pong {
                version: VERSION.to_string(),
                protection_active: !self.active.lock().is_empty(),
            },
            Command::ListProfiles => Response::Profiles(self.store.list_profiles()?),
            Command::ListSites { profile_id } => {
                Response::Sites(self.store.list_sites(profile_id.as_deref())?)
            }
            Command::UpsertProfile { profile } => {
                self.store.upsert_profile(&profile)?;
                Response::Profile(profile)
            }
            Command::UpsertSite { mut site } => {
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
                // Full rebuild so disable never leaves orphan IP blocks (QUIC errors).
                if let Err(e) = self.reapply_enabled() {
                    eprintln!("[at-shield] reapply after upsert: {e}");
                }
                Response::Site(site)
            }
            Command::DeleteSite { id } => {
                self.delete_site_and_aliases(&id)?;
                if let Err(e) = self.reapply_enabled() {
                    eprintln!("[at-shield] reapply after delete: {e}");
                }
                Response::Empty
            }
            Command::SetEnabled { id, enabled } => {
                let mut site = self
                    .store
                    .get_site(&id)?
                    .ok_or_else(|| format!("site not found: {id}"))?;
                site.enabled = enabled;
                self.store.upsert_site(&site)?;
                let _ = self.set_aliases_enabled(&site);
                if let Err(e) = self.reapply_enabled() {
                    eprintln!("[at-shield] reapply after set_enabled: {e}");
                }
                Response::Site(
                    self.store
                        .get_site(&id)?
                        .unwrap_or(site),
                )
            }
            Command::SetEnabledBatch { ids, enabled } => {
                // ponytail: one round-trip from UI; rebuild WFP once after DB writes
                let mut changed = Vec::new();
                for id in &ids {
                    if let Some(mut site) = self.store.get_site(id)? {
                        site.enabled = enabled;
                        self.store.upsert_site(&site)?;
                        let _ = self.set_aliases_enabled(&site);
                        changed.push(site);
                    }
                }
                if let Err(e) = self.reapply_enabled() {
                    eprintln!("[at-shield] reapply after set_enabled_batch: {e}");
                }
                Response::Sites(changed)
            }
            Command::ApplyProfile { profile_id } => {
                let sites = self.store.list_sites(Some(&profile_id))?;
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
                Response::Sites(enabled)
            }
            Command::SetRedirectPage { id, page_file } => {
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
                let profiles = self.store.list_profiles()?;
                let profile = profiles
                    .into_iter()
                    .find(|p| p.id == profile_id)
                    .ok_or_else(|| format!("profile not found: {profile_id}"))?;
                // apply profile rules immediately
                let _ = self.handle_inner(Command::ApplyProfile {
                    profile_id: profile_id.clone(),
                })?;
                *self.session.lock() = Some(LiveSession {
                    profile_id: profile.id.clone(),
                    profile_name: profile.name.clone(),
                    state: SessionState::Running,
                    duration_secs,
                    remaining_secs: duration_secs,
                    tick_at: Instant::now(),
                });
                Response::Session(self.snapshot_session())
            }
            Command::PauseSession => {
                let mut g = self.session.lock();
                if let Some(sess) = g.as_mut() {
                    Self::refresh_session_clock(sess);
                    sess.state = SessionState::Paused;
                    // release network filters while paused
                    let _ = self.filter.clear_all();
                    self.active.lock().clear();
                }
                drop(g);
                Response::Session(self.snapshot_session())
            }
            Command::ResumeSession => {
                let mut g = self.session.lock();
                if let Some(sess) = g.as_mut() {
                    if sess.state == SessionState::Paused {
                        sess.state = SessionState::Running;
                        sess.tick_at = Instant::now();
                        let pid = sess.profile_id.clone();
                        drop(g);
                        let _ = self.handle_inner(Command::ApplyProfile { profile_id: pid })?;
                        return Ok(Response::Session(self.snapshot_session()));
                    }
                }
                drop(g);
                Response::Session(self.snapshot_session())
            }
            Command::EndSession => {
                *self.session.lock() = None;
                self.reapply_enabled()?;
                Response::Session(None)
            }
            Command::GetSession => Response::Session(self.snapshot_session()),
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
            profile_id: Some("profile-trabalho".into()),
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
            profile_id: Some("profile-trabalho".into()),
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
            profile_id: Some("profile-trabalho".into()),
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
            profile_id: Some("profile-trabalho".into()),
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
                profile_id: "profile-trabalho".into(),
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
            profile_id: Some("profile-trabalho".into()),
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
    fn batch_toggle_updates_noop_filter() {
        let dir = std::env::temp_dir().join(format!("at-shield-test-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter.clone()).unwrap();
        eng.warm_protection().unwrap();
        let sites = match eng.handle(Command::ListSites { profile_id: None }) {
            Response::Sites(s) => s,
            _ => panic!("expected sites"),
        };
        assert!(!sites.is_empty());
        let ids: Vec<_> = sites.iter().map(|s| s.id.clone()).collect();
        eng.handle(Command::SetEnabledBatch {
            ids: ids.clone(),
            enabled: false,
        });
        assert!(filter.applied.lock().is_empty());
        eng.handle(Command::SetEnabledBatch {
            ids,
            enabled: true,
        });
        assert!(!filter.applied.lock().is_empty());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn session_pause_clears_filters() {
        let dir = std::env::temp_dir().join(format!("at-shield-sess-{}", uuid::Uuid::new_v4()));
        let store = Store::open(dir.join("t.db")).unwrap();
        let filter = Arc::new(NoopFilter::default());
        let eng = Engine::new(store, filter.clone()).unwrap();
        eng.warm_protection().unwrap();
        eng.handle(Command::StartSession {
            profile_id: "profile-trabalho".into(),
            duration_secs: 3600,
        });
        assert!(!filter.applied.lock().is_empty());
        eng.handle(Command::PauseSession);
        assert!(filter.applied.lock().is_empty());
        eng.handle(Command::ResumeSession);
        assert!(!filter.applied.lock().is_empty());
        eng.handle(Command::EndSession);
        let _ = std::fs::remove_dir_all(dir);
    }
}
