use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Profile {
    pub id: String,
    pub name: String,
    pub sort_order: i32,
}

impl Profile {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.into(),
            sort_order: 0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum RedirectTarget {
    CustomPage,
    Block,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SiteRule {
    pub id: String,
    pub profile_id: String,
    pub domain: String,
    pub include_subdomains: bool,
    pub redirect: RedirectTarget,
    pub page_file: String,
    pub http: bool,
    pub https: bool,
    pub enabled: bool,
}

impl SiteRule {
    pub fn new(profile_id: impl Into<String>, domain: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            profile_id: profile_id.into(),
            domain: domain.into(),
            include_subdomains: true,
            redirect: RedirectTarget::CustomPage,
            page_file: "foco.html".into(),
            http: false,
            https: true,
            enabled: true,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    Idle,
    Running,
    Paused,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct FocusSession {
    pub profile_id: String,
    pub profile_name: String,
    pub state: SessionState,
    pub remaining_secs: u64,
    pub duration_secs: u64,
}
