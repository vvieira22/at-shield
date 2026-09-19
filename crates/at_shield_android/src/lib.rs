//! Android adapter stub — VpnService in a later phase.
//! Same NetworkFilter surface so core/UI stay unchanged.

use at_shield_core::{FilterError, NetworkFilter, NoopFilter, SiteRule};

/// Placeholder until VpnService is wired. Behaves like NoopFilter.
pub struct AndroidFilter {
    inner: NoopFilter,
}

impl Default for AndroidFilter {
    fn default() -> Self {
        Self {
            inner: NoopFilter::default(),
        }
    }
}

impl AndroidFilter {
    pub fn new() -> Self {
        Self::default()
    }
}

impl NetworkFilter for AndroidFilter {
    fn name(&self) -> &'static str {
        "android_vpn_stub"
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
