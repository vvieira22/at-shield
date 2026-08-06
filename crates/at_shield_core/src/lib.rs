//! A.T. Shield core — rules in memory, SQLite only for persistence.

mod engine;
mod filter;
mod models;
mod store;

pub use engine::Engine;
pub use filter::{FilterError, NetworkFilter, NoopFilter};
pub use models::*;
pub use store::Store;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "cmd", rename_all = "snake_case")]
pub enum Command {
    /// Optional `ui_pid` lets the service reap the session the instant the UI process dies.
    Health {
        #[serde(default)]
        ui_pid: Option<u32>,
    },
    ListProfiles,
    ListSites { profile_id: Option<String> },
    UpsertProfile { profile: Profile },
    DeleteProfile { id: String },
    UpsertSite { site: SiteRule },
    DeleteSite { id: String },
    SetEnabled { id: String, enabled: bool },
    SetEnabledBatch { ids: Vec<String>, enabled: bool },
    ApplyProfile { profile_id: String },
    SetRedirectPage { id: String, page_file: String },
    StartSession {
        profile_id: String,
        duration_secs: u64,
    },
    EndSession,
    GetSession,
    /// Take the summary left by timer auto-end (or last EndSession).
    PopSessionSummary,
    ListSessionHistory,
    ClearSessionHistory,
    /// UI liveness ping — if this stops while a session is on, protection is cleared.
    UiHeartbeat,
    /// Session parked after UI process death (blocks already cleared).
    GetInterruptedSession,
    /// Re-arm network and continue the parked timer.
    RestoreInterruptedSession,
    /// Drop the parked session — open clean.
    DiscardInterruptedSession,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "ok", content = "data", rename_all = "snake_case")]
pub enum Response {
    Pong {
        version: String,
        protection_active: bool,
        /// WFP/hosts actually live (false = tracking-only, precisa Admin).
        network_armed: bool,
        /// Focus session currently active.
        session_active: bool,
        /// Enabled site rules in DB (any profile).
        enabled_sites: u32,
    },
    Profiles(Vec<Profile>),
    Sites(Vec<SiteRule>),
    Site(SiteRule),
    Profile(Profile),
    Session(Option<FocusSession>),
    SessionSummary(Option<SessionRecord>),
    SessionHistory(Vec<SessionRecord>),
    InterruptedSession(Option<InterruptedSession>),
    Empty,
    Error { message: String },
}

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const PIPE_NAME: &str = r"\\.\pipe\at-shield";
