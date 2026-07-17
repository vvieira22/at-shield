//! Linux stub — nftables/iptables adapter later.
use at_shield_core::{FilterError, NetworkFilter, NoopFilter, SiteRule};

pub struct LinuxFilter {
    inner: NoopFilter,
}

impl Default for LinuxFilter {
    fn default() -> Self {
        Self {
            inner: NoopFilter::default(),
        }
    }
}

impl LinuxFilter {
    pub fn new() -> Self {
        Self::default()
    }
}

impl NetworkFilter for LinuxFilter {
    fn name(&self) -> &'static str {
        "linux_nft_stub"
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
