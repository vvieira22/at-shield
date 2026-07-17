//! Windows adapter: WFP hard-block + hosts sinkhole for custom HTML pages.
//!
//! - RedirectTarget::Block       → WFP IP drop
//! - RedirectTarget::CustomPage  → hosts → 127.0.0.1 + local :80/:443 page server
//!
//! ponytail: without elevation WFP/hosts/port 80-443 fail → tracking-only.

mod hosts;
mod page_server;
mod wfp;

use at_shield_core::{FilterError, NetworkFilter, RedirectTarget, SiteRule};
use parking_lot::Mutex;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

pub use page_server::PageServer;

pub struct WindowsFilter {
    inner: Mutex<Inner>,
    pages: Option<Arc<PageServer>>,
}

struct Inner {
    wfp: Option<wfp::WfpEngine>,
    /// domain -> applied rule
    applied: HashMap<String, SiteRule>,
}

impl WindowsFilter {
    pub fn new(pages_dir: Option<PathBuf>, cert_dir: PathBuf) -> Result<Self, String> {
        let wfp = match wfp::WfpEngine::open() {
            Ok(e) => {
                eprintln!("[at-shield] WFP engine open OK");
                Some(e)
            }
            Err(e) => {
                eprintln!("[at-shield] WFP unavailable ({e}) — tracking-only until elevated");
                None
            }
        };
        let pages = if let Some(dir) = pages_dir {
            match PageServer::start(dir, cert_dir, 47831) {
                Ok(p) => {
                    eprintln!("[at-shield] page preview http://127.0.0.1:47831");
                    Some(Arc::new(p))
                }
                Err(e) => {
                    eprintln!("[at-shield] page server failed: {e}");
                    None
                }
            }
        } else {
            None
        };
        Ok(Self {
            inner: Mutex::new(Inner {
                wfp,
                applied: HashMap::new(),
            }),
            pages,
        })
    }

    pub fn page_server_port(&self) -> Option<u16> {
        self.pages.as_ref().map(|p| p.port())
    }

    /// Emergency: wipe every ATShield WFP filter + hosts block. Call as Admin.
    pub fn nuke_all_blocks() -> Result<(), String> {
        match wfp::WfpEngine::open() {
            Ok(mut e) => {
                e.clear()?;
                drop(e);
            }
            Err(e) => return Err(format!("WFP open (precisa Admin): {e}")),
        }
        hosts::clear()?;
        let _ = std::process::Command::new("ipconfig")
            .args(["/flushdns"])
            .output();
        Ok(())
    }

    fn sync_hosts_from_applied(applied: &HashMap<String, SiteRule>) -> Result<(), String> {
        let mut lines = Vec::new();
        let mut seen = std::collections::HashSet::new();
        for site in applied.values() {
            if site.redirect != RedirectTarget::CustomPage {
                continue;
            }
            for line in hosts::lines_for(&site.domain, site.include_subdomains) {
                if seen.insert(line.clone()) {
                    lines.push(line);
                }
            }
        }
        hosts::rewrite(&lines)
    }
}

impl NetworkFilter for WindowsFilter {
    fn name(&self) -> &'static str {
        "windows_wfp_hosts"
    }

    fn apply(&self, site: &SiteRule) -> Result<(), FilterError> {
        let mut g = self.inner.lock();
        // Drop any previous mode for this domain first.
        if let Some(wfp) = g.wfp.as_mut() {
            let _ = wfp.unblock_domain(&site.domain);
        }
        if let Some(pages) = &self.pages {
            pages.clear_route(&site.domain);
        }

        match site.redirect {
            RedirectTarget::Block => {
                if let Some(wfp) = g.wfp.as_mut() {
                    wfp.block_domain(&site.domain, site.include_subdomains)
                        .map_err(FilterError)?;
                }
            }
            RedirectTarget::CustomPage => {
                if let Some(pages) = &self.pages {
                    pages.set_route(&site.domain, &site.page_file, site.include_subdomains);
                }
            }
        }
        g.applied.insert(site.domain.clone(), site.clone());
        Self::sync_hosts_from_applied(&g.applied).map_err(FilterError)?;
        Ok(())
    }

    fn remove(&self, site: &SiteRule) -> Result<(), FilterError> {
        let mut g = self.inner.lock();
        if let Some(wfp) = g.wfp.as_mut() {
            wfp.unblock_domain(&site.domain).map_err(FilterError)?;
        }
        if let Some(pages) = &self.pages {
            pages.clear_route(&site.domain);
        }
        g.applied.remove(&site.domain);
        Self::sync_hosts_from_applied(&g.applied).map_err(FilterError)?;
        Ok(())
    }

    fn clear_all(&self) -> Result<(), FilterError> {
        let mut g = self.inner.lock();
        if let Some(wfp) = g.wfp.as_mut() {
            wfp.clear().map_err(FilterError)?;
        }
        if let Some(pages) = &self.pages {
            pages.clear_routes();
        }
        g.applied.clear();
        hosts::clear().map_err(FilterError)?;
        Ok(())
    }
}
