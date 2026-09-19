use crate::models::*;
use rusqlite::{params, Connection};
use serde::{de::DeserializeOwned, Serialize};
use std::path::{Path, PathBuf};

pub struct Store {
    path: PathBuf,
}

impl Store {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, String> {
        let path = path.as_ref().to_path_buf();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let s = Self { path };
        s.migrate()?;
        Ok(s)
    }

    fn conn(&self) -> Result<Connection, String> {
        Connection::open(&self.path).map_err(|e| e.to_string())
    }

    fn migrate(&self) -> Result<(), String> {
        let c = self.conn()?;
        c.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS profiles (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS sites (
              id TEXT PRIMARY KEY,
              profile_id TEXT NOT NULL,
              domain TEXT NOT NULL,
              include_subdomains INTEGER NOT NULL DEFAULT 1,
              redirect TEXT NOT NULL DEFAULT 'custom_page',
              page_file TEXT NOT NULL DEFAULT 'foco.html',
              http INTEGER NOT NULL DEFAULT 0,
              https INTEGER NOT NULL DEFAULT 1,
              enabled INTEGER NOT NULL DEFAULT 1,
              FOREIGN KEY(profile_id) REFERENCES profiles(id)
            );
            CREATE TABLE IF NOT EXISTS settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS session_history (
              id TEXT PRIMARY KEY,
              profile_id TEXT NOT NULL,
              profile_name TEXT NOT NULL,
              started_at INTEGER NOT NULL,
              ended_at INTEGER NOT NULL,
              duration_secs INTEGER NOT NULL,
              elapsed_secs INTEGER NOT NULL,
              ended_reason TEXT NOT NULL,
              total_attempts INTEGER NOT NULL DEFAULT 0,
              attempts_json TEXT NOT NULL DEFAULT '[]'
            );
            "#,
        )
        .map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Built-in profiles — always present, never deletable.
    pub const BUILTIN_PROFILES: &[&str] = &[
        "profile-estudo",
        "profile-detox-total",
        "profile-adulto",
    ];

    pub fn is_builtin_profile(id: &str) -> bool {
        Self::BUILTIN_PROFILES.contains(&id)
    }

    /// Ensures the three built-in profiles exist with a lean site list.
    /// Also removes leftover seed profiles from older versions.
    pub fn seed_if_empty(&self) -> Result<(), String> {
        for stale in ["profile-trabalho", "profile-estudos", "profile-detox"] {
            if self.list_profiles()?.iter().any(|p| p.id == stale) {
                self.delete_profile(stale)?;
            }
        }
        // Estudo — top distractions while studying
        self.ensure_default_profile(
            "profile-estudo",
            "Estudo",
            0,
            &[
                ("youtube.com", "foco.html"),
                ("instagram.com", "foco.html"),
                ("tiktok.com", "foco.html"),
                ("twitter.com", "foco.html"),
                ("x.com", "foco.html"),
                ("facebook.com", "foco.html"),
                ("reddit.com", "foco.html"),
                ("discord.com", "foco.html"),
                ("twitch.tv", "foco.html"),
            ],
        )?;
        // Detox total — social + entertainment
        self.ensure_default_profile(
            "profile-detox-total",
            "Detox total",
            1,
            &[
                ("instagram.com", "detox.html"),
                ("facebook.com", "detox.html"),
                ("tiktok.com", "detox.html"),
                ("twitter.com", "detox.html"),
                ("x.com", "detox.html"),
                ("youtube.com", "detox.html"),
                ("reddit.com", "detox.html"),
                ("netflix.com", "detox.html"),
                ("twitch.tv", "detox.html"),
                ("discord.com", "detox.html"),
                ("whatsapp.com", "detox.html"),
                ("pinterest.com", "detox.html"),
            ],
        )?;
        // Adulto — most-visited adult sites
        self.ensure_default_profile(
            "profile-adulto",
            "Adulto",
            2,
            &[
                ("pornhub.com", "foco.html"),
                ("xvideos.com", "foco.html"),
                ("xnxx.com", "foco.html"),
                ("xhamster.com", "foco.html"),
                ("onlyfans.com", "foco.html"),
                ("chaturbate.com", "foco.html"),
                ("redtube.com", "foco.html"),
                ("spankbang.com", "foco.html"),
                ("erome.com", "foco.html"),
            ],
        )?;
        Ok(())
    }

    fn ensure_default_profile(
        &self,
        id: &str,
        name: &str,
        sort_order: i32,
        sites: &[(&str, &str)],
    ) -> Result<(), String> {
        let exists = self.list_profiles()?.iter().any(|p| p.id == id);
        if !exists {
            self.upsert_profile(&Profile {
                id: id.into(),
                name: name.into(),
                sort_order,
            })?;
        }
        let existing = self.list_sites(Some(id))?;
        for &(domain, page) in sites {
            if existing.iter().any(|s| s.domain == domain) {
                continue;
            }
            let mut s = SiteRule::new(id, domain);
            s.page_file = page.into();
            self.upsert_site(&s)?;
        }
        Ok(())
    }

    pub fn list_profiles(&self) -> Result<Vec<Profile>, String> {
        let c = self.conn()?;
        let mut stmt = c
            .prepare("SELECT id, name, sort_order FROM profiles ORDER BY sort_order, name")
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |r| {
                Ok(Profile {
                    id: r.get(0)?,
                    name: r.get(1)?,
                    sort_order: r.get(2)?,
                })
            })
            .map_err(|e| e.to_string())?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())
    }

    pub fn upsert_profile(&self, p: &Profile) -> Result<(), String> {
        self.conn()?
            .execute(
                "INSERT INTO profiles(id,name,sort_order) VALUES(?1,?2,?3)
                 ON CONFLICT(id) DO UPDATE SET name=excluded.name, sort_order=excluded.sort_order",
                params![p.id, p.name, p.sort_order],
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn list_sites(&self, profile_id: Option<&str>) -> Result<Vec<SiteRule>, String> {
        let c = self.conn()?;
        let map_row = |r: &rusqlite::Row| -> rusqlite::Result<SiteRule> {
            let redirect: String = r.get(4)?;
            Ok(SiteRule {
                id: r.get(0)?,
                profile_id: r.get(1)?,
                domain: r.get(2)?,
                include_subdomains: r.get::<_, i64>(3)? != 0,
                redirect: if redirect == "block" {
                    RedirectTarget::Block
                } else {
                    RedirectTarget::CustomPage
                },
                page_file: r.get(5)?,
                http: r.get::<_, i64>(6)? != 0,
                https: r.get::<_, i64>(7)? != 0,
                enabled: r.get::<_, i64>(8)? != 0,
            })
        };
        if let Some(pid) = profile_id {
            let mut stmt = c
                .prepare(
                    "SELECT id,profile_id,domain,include_subdomains,redirect,page_file,http,https,enabled
                     FROM sites WHERE profile_id=?1 ORDER BY domain",
                )
                .map_err(|e| e.to_string())?;
            let rows = stmt
                .query_map(params![pid], map_row)
                .map_err(|e| e.to_string())?;
            rows.collect::<Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())
        } else {
            let mut stmt = c
                .prepare(
                    "SELECT id,profile_id,domain,include_subdomains,redirect,page_file,http,https,enabled
                     FROM sites ORDER BY domain",
                )
                .map_err(|e| e.to_string())?;
            let rows = stmt.query_map([], map_row).map_err(|e| e.to_string())?;
            rows.collect::<Result<Vec<_>, _>>()
                .map_err(|e| e.to_string())
        }
    }

    pub fn upsert_site(&self, s: &SiteRule) -> Result<(), String> {
        let redirect = match s.redirect {
            RedirectTarget::CustomPage => "custom_page",
            RedirectTarget::Block => "block",
        };
        self.conn()?
            .execute(
                "INSERT INTO sites(id,profile_id,domain,include_subdomains,redirect,page_file,http,https,enabled)
                 VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)
                 ON CONFLICT(id) DO UPDATE SET
                   profile_id=excluded.profile_id,
                   domain=excluded.domain,
                   include_subdomains=excluded.include_subdomains,
                   redirect=excluded.redirect,
                   page_file=excluded.page_file,
                   http=excluded.http,
                   https=excluded.https,
                   enabled=excluded.enabled",
                params![
                    s.id,
                    s.profile_id,
                    s.domain,
                    s.include_subdomains as i64,
                    redirect,
                    s.page_file,
                    s.http as i64,
                    s.https as i64,
                    s.enabled as i64,
                ],
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn delete_site(&self, id: &str) -> Result<(), String> {
        self.conn()?
            .execute("DELETE FROM sites WHERE id=?1", params![id])
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn delete_profile(&self, id: &str) -> Result<(), String> {
        let c = self.conn()?;
        c.execute("DELETE FROM sites WHERE profile_id=?1", params![id])
            .map_err(|e| e.to_string())?;
        c.execute("DELETE FROM profiles WHERE id=?1", params![id])
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn get_site(&self, id: &str) -> Result<Option<SiteRule>, String> {
        Ok(self.list_sites(None)?.into_iter().find(|s| s.id == id))
    }

    pub fn insert_session_record(&self, r: &SessionRecord) -> Result<(), String> {
        let attempts_json =
            serde_json::to_string(&r.attempts).map_err(|e| e.to_string())?;
        self.conn()?
            .execute(
                "INSERT INTO session_history(
                   id, profile_id, profile_name, started_at, ended_at,
                   duration_secs, elapsed_secs, ended_reason, total_attempts, attempts_json
                 ) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)",
                params![
                    r.id,
                    r.profile_id,
                    r.profile_name,
                    r.started_at,
                    r.ended_at,
                    r.duration_secs as i64,
                    r.elapsed_secs as i64,
                    r.ended_reason,
                    r.total_attempts as i64,
                    attempts_json,
                ],
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn list_session_history(&self) -> Result<Vec<SessionRecord>, String> {
        self.purge_session_history_older_than(30 * 24 * 60 * 60)?;
        let c = self.conn()?;
        let mut stmt = c
            .prepare(
                "SELECT id, profile_id, profile_name, started_at, ended_at,
                        duration_secs, elapsed_secs, ended_reason, total_attempts, attempts_json
                 FROM session_history ORDER BY started_at DESC",
            )
            .map_err(|e| e.to_string())?;
        let rows = stmt
            .query_map([], |row| {
                let attempts_json: String = row.get(9)?;
                let attempts: Vec<DomainHit> =
                    serde_json::from_str(&attempts_json).unwrap_or_default();
                Ok(SessionRecord {
                    id: row.get(0)?,
                    profile_id: row.get(1)?,
                    profile_name: row.get(2)?,
                    started_at: row.get(3)?,
                    ended_at: row.get(4)?,
                    duration_secs: row.get::<_, i64>(5)? as u64,
                    elapsed_secs: row.get::<_, i64>(6)? as u64,
                    ended_reason: row.get(7)?,
                    total_attempts: row.get::<_, i64>(8)? as u32,
                    attempts,
                })
            })
            .map_err(|e| e.to_string())?;
        rows.collect::<Result<Vec<_>, _>>()
            .map_err(|e| e.to_string())
    }

    /// Delete history older than `max_age_secs` (based on `started_at`).
    pub fn purge_session_history_older_than(&self, max_age_secs: i64) -> Result<u32, String> {
        let cutoff = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0)
            .saturating_sub(max_age_secs);
        let n = self
            .conn()?
            .execute(
                "DELETE FROM session_history WHERE started_at < ?1",
                params![cutoff],
            )
            .map_err(|e| e.to_string())?;
        Ok(n as u32)
    }

    pub fn clear_session_history(&self) -> Result<(), String> {
        self.conn()?
            .execute("DELETE FROM session_history", [])
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    const INTERRUPTED_KEY: &'static str = "interrupted_session";
    const LIVE_KEY: &'static str = "live_session_checkpoint";

    fn get_setting_json<T: DeserializeOwned>(&self, key: &str) -> Result<Option<T>, String> {
        let c = self.conn()?;
        let mut stmt = c
            .prepare("SELECT value FROM settings WHERE key=?1")
            .map_err(|e| e.to_string())?;
        let mut rows = stmt.query(params![key]).map_err(|e| e.to_string())?;
        let Some(row) = rows.next().map_err(|e| e.to_string())? else {
            return Ok(None);
        };
        let raw: String = row.get(0).map_err(|e| e.to_string())?;
        let parsed: T = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
        Ok(Some(parsed))
    }

    fn set_setting_json<T: Serialize>(&self, key: &str, value: &T) -> Result<(), String> {
        let raw = serde_json::to_string(value).map_err(|e| e.to_string())?;
        self.conn()?
            .execute(
                "INSERT INTO settings(key, value) VALUES(?1, ?2)
                 ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                params![key, raw],
            )
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    fn clear_setting(&self, key: &str) -> Result<(), String> {
        self.conn()?
            .execute("DELETE FROM settings WHERE key=?1", params![key])
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn get_interrupted_session(&self) -> Result<Option<InterruptedSession>, String> {
        self.get_setting_json(Self::INTERRUPTED_KEY)
    }

    pub fn set_interrupted_session(&self, s: &InterruptedSession) -> Result<(), String> {
        self.set_setting_json(Self::INTERRUPTED_KEY, s)
    }

    pub fn clear_interrupted_session(&self) -> Result<(), String> {
        self.clear_setting(Self::INTERRUPTED_KEY)
    }

    pub fn set_live_checkpoint(&self, s: &InterruptedSession) -> Result<(), String> {
        self.set_setting_json(Self::LIVE_KEY, s)
    }

    pub fn take_live_checkpoint(&self) -> Result<Option<InterruptedSession>, String> {
        let v = self.get_setting_json(Self::LIVE_KEY)?;
        let _ = self.clear_setting(Self::LIVE_KEY);
        Ok(v)
    }

    pub fn clear_live_checkpoint(&self) -> Result<(), String> {
        self.clear_setting(Self::LIVE_KEY)
    }
}
