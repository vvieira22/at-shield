//! macOS stub — Network Extension / PF later.
use at_shield_core::{FilterError, NetworkFilter, NoopFilter, SiteRule};

pub struct MacosFilter {
    inner: NoopFilter,
}

impl Default for MacosFilter {
    fn default() -> Self {
        Self {
            inner: NoopFilter::default(),
        }
    }
}

impl MacosFilter {
    pub fn new() -> Self {
        Self::default()
    }
}

impl NetworkFilter for MacosFilter {
    fn name(&self) -> &'static str {
        "macos_ne_stub"
    }
    fn apply(&self, site: &SiteRule) -> Result<(), FilterError> {
        self.inner.apply(site)
    }
    fn remove(&self, site: &SiteRule) -> Result<(), FilterError> {
        self.inner.remove(site)
    }
    fn clear_all(&self) -> Result<(), FilterError> {
        self.inner.clear_all()
    }
}
