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
    Health,
    ListProfiles,
    ListSites { profile_id: Option<String> },
    UpsertProfile { profile: Profile },
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
    PauseSession,
    ResumeSession,
    EndSession,
    GetSession,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "ok", content = "data", rename_all = "snake_case")]
pub enum Response {
    Pong {
        version: String,
        protection_active: bool,
    },
    Profiles(Vec<Profile>),
    Sites(Vec<SiteRule>),
    Site(SiteRule),
    Profile(Profile),
    Session(Option<FocusSession>),
    Empty,
    Error { message: String },
}

pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const PIPE_NAME: &str = r"\\.\pipe\at-shield";
