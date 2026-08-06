//! Windows adapter: WFP hard-block + hosts sinkhole for custom HTML pages.
//!
//! - RedirectTarget::Block       → WFP IP drop
//! - RedirectTarget::CustomPage  → hosts → 127.0.0.2 + page server on that IP :80/:443
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
    /// Last hosts/WFP write succeeded (needs Admin).
    armed: Mutex<bool>,
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
            armed: Mutex::new(false),
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

    /// MSI uninstall: nuke WFP/hosts, drop sinkhole Root cert, remove ProgramData\ATShield.
    pub fn uninstall_cleanup() -> Result<(), String> {
        if let Err(e) = Self::nuke_all_blocks() {
            eprintln!("[at-shield] uninstall nuke: {e}");
        }
        let base = std::env::var("PROGRAMDATA").unwrap_or_else(|_| r"C:\ProgramData".into());
        let data = PathBuf::from(&base).join("ATShield");
        let cer = data.join("certs").join("sinkhole.cer");
        page_server::remove_ca_trust(&cer);
        match std::fs::remove_dir_all(&data) {
            Ok(()) => eprintln!("[at-shield] removed {}", data.display()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => eprintln!("[at-shield] remove {}: {e}", data.display()),
        }
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

    fn mark_armed(&self, ok: bool) {
        *self.armed.lock() = ok;
    }
}

impl NetworkFilter for WindowsFilter {
    fn name(&self) -> &'static str {
        "windows_wfp_hosts"
    }

    fn network_armed(&self) -> bool {
        *self.armed.lock()
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

        let mut step_ok = true;
        match site.redirect {
            RedirectTarget::Block => {
                if let Some(wfp) = g.wfp.as_mut() {
                    if let Err(e) = wfp.block_domain(&site.domain, site.include_subdomains) {
                        eprintln!("[at-shield] WFP block (precisa Admin): {e}");
                        step_ok = false;
                    }
                } else {
                    step_ok = false;
                }
            }
            RedirectTarget::CustomPage => {
                if let Some(pages) = &self.pages {
                    pages.set_route(&site.domain, &site.page_file, site.include_subdomains);
                }
            }
        }
        g.applied.insert(site.domain.clone(), site.clone());
        let has_pages = g
            .applied
            .values()
            .any(|s| s.redirect == RedirectTarget::CustomPage);
        // ponytail: hosts/WFP need Admin — never abort the session; stay tracking-only
        if let Err(e) = Self::sync_hosts_from_applied(&g.applied) {
            eprintln!("[at-shield] hosts sync (precisa Admin): {e}");
            if has_pages {
                step_ok = false;
            }
        }
        self.mark_armed(step_ok);
        Ok(())
    }

    fn remove(&self, site: &SiteRule) -> Result<(), FilterError> {
        let mut g = self.inner.lock();
        if let Some(wfp) = g.wfp.as_mut() {
            if let Err(e) = wfp.unblock_domain(&site.domain) {
                eprintln!("[at-shield] WFP unblock: {e}");
            }
        }
        if let Some(pages) = &self.pages {
            pages.clear_route(&site.domain);
        }
        g.applied.remove(&site.domain);
        if let Err(e) = Self::sync_hosts_from_applied(&g.applied) {
            eprintln!("[at-shield] hosts sync (precisa Admin): {e}");
            self.mark_armed(false);
        }
        Ok(())
    }

    fn clear_all(&self) -> Result<(), FilterError> {
        let mut g = self.inner.lock();
        if let Some(wfp) = g.wfp.as_mut() {
            if let Err(e) = wfp.clear() {
                eprintln!("[at-shield] WFP clear (precisa Admin): {e}");
            }
        }
        if let Some(pages) = &self.pages {
            pages.clear_routes();
        }
        g.applied.clear();
        if let Err(e) = hosts::clear() {
            eprintln!("[at-shield] hosts clear (precisa Admin): {e}");
            self.mark_armed(false);
            return Ok(());
        }
        self.mark_armed(false);
        Ok(())
    }

    fn reset_block_hits(&self) {
        if let Some(pages) = &self.pages {
            pages.reset_hits();
        }
    }

    fn drain_block_hits(&self) -> Vec<(String, u32)> {
        self.pages
            .as_ref()
            .map(|p| p.drain_hits())
            .unwrap_or_default()
    }
}

impl Drop for WindowsFilter {
    fn drop(&mut self) {
        // WFP DYNAMIC dies with the process; hosts file does NOT — always wipe.
        eprintln!("[at-shield] filter drop — limpando hosts/rotas");
        if let Some(pages) = &self.pages {
            pages.clear_routes();
        }
        if let Err(e) = hosts::clear() {
            eprintln!("[at-shield] hosts clear on drop: {e}");
        }
        let mut g = self.inner.lock();
        if let Some(wfp) = g.wfp.as_mut() {
            let _ = wfp.clear();
        }
        g.applied.clear();
    }
}
