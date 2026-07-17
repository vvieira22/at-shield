use crate::SiteRule;
use std::fmt;

/// Platform adapter: apply / remove block rules. Hot path must be fast.
pub trait NetworkFilter: Send + Sync {
    fn name(&self) -> &'static str;
    fn apply(&self, site: &SiteRule) -> Result<(), FilterError>;
    fn remove(&self, site: &SiteRule) -> Result<(), FilterError>;
    fn apply_batch(&self, sites: &[SiteRule]) -> Result<(), FilterError> {
        for s in sites {
            self.apply(s)?;
        }
        Ok(())
    }
    fn remove_batch(&self, sites: &[SiteRule]) -> Result<(), FilterError> {
        for s in sites {
            self.remove(s)?;
        }
        Ok(())
    }
    fn clear_all(&self) -> Result<(), FilterError>;
}

#[derive(Debug)]
pub struct FilterError(pub String);

impl fmt::Display for FilterError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl std::error::Error for FilterError {}

/// Dev / unsupported platforms — tracks intent without touching the OS network stack.
pub struct NoopFilter {
    pub applied: parking_lot::Mutex<Vec<String>>,
}

impl Default for NoopFilter {
    fn default() -> Self {
        Self {
            applied: parking_lot::Mutex::new(Vec::new()),
        }
    }
}

impl NetworkFilter for NoopFilter {
    fn name(&self) -> &'static str {
        "noop"
    }

    fn apply(&self, site: &SiteRule) -> Result<(), FilterError> {
        let mut g = self.applied.lock();
        if !g.iter().any(|d| d == &site.domain) {
            g.push(site.domain.clone());
        }
        Ok(())
    }

    fn remove(&self, site: &SiteRule) -> Result<(), FilterError> {
        self.applied.lock().retain(|d| d != &site.domain);
        Ok(())
    }

    fn clear_all(&self) -> Result<(), FilterError> {
        self.applied.lock().clear();
        Ok(())
    }
}
