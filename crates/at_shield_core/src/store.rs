use crate::models::*;
use rusqlite::{params, Connection};
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

    pub fn seed_if_empty(&self) -> Result<(), String> {
        let c = self.conn()?;
        let n: i64 = c
            .query_row("SELECT COUNT(*) FROM profiles", [], |r| r.get(0))
            .map_err(|e| e.to_string())?;
        if n > 0 {
            return Ok(());
        }
        drop(c);
        let trabalho = Profile {
            id: "profile-trabalho".into(),
            name: "Trabalho".into(),
            sort_order: 0,
        };
        let estudos = Profile {
            id: "profile-estudos".into(),
            name: "Estudos".into(),
            sort_order: 1,
        };
        let detox = Profile {
            id: "profile-detox".into(),
            name: "Detox".into(),
            sort_order: 2,
        };
        self.upsert_profile(&trabalho)?;
        self.upsert_profile(&estudos)?;
        self.upsert_profile(&detox)?;

        let seeds = [
            ("instagram.com", "foco.html", true),
            ("facebook.com", "foco.html", true),
            ("twitter.com", "detox.html", true),
            ("tiktok.com", "detox.html", true),
            ("youtube.com", "foco.html", false),
            ("reddit.com", "foco.html", true),
            ("netflix.com", "detox.html", false),
            ("twitch.tv", "foco.html", true),
            ("linkedin.com", "foco.html", false),
            ("pinterest.com", "detox.html", true),
            ("discord.com", "foco.html", true),
            ("x.com", "detox.html", true),
        ];
        for (domain, page, enabled) in seeds {
            let mut s = SiteRule::new(&trabalho.id, domain);
            s.page_file = page.into();
            s.enabled = enabled;
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
}
