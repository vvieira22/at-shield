//! WFP user-mode block by resolved IPv4.
//! Needs admin for FwpmEngineOpen0; without it open() returns Err.
//!
//! ponytail: IP refcount — Meta (facebook/instagram) and CDNs share edges; one
//! WFP filter per IP, dropped only when the last domain releases it.

use std::collections::HashMap;
use std::net::ToSocketAddrs;

#[cfg(windows)]
mod win {
    use super::*;
    use windows::core::{GUID, PCWSTR, PWSTR};
    use windows::Win32::Foundation::{ERROR_SUCCESS, HANDLE};
    use windows::Win32::NetworkManagement::WindowsFilteringPlatform::*;
    use windows::Win32::System::Rpc::RPC_C_AUTHN_WINNT;

    // Fixed provider GUID for A.T. Shield (do not change once shipped)
    const PROVIDER_KEY: GUID = GUID::from_u128(0xA75A_1E1D_5E1D_4B10_9C2A_7E11D00D5E1Du128);

    pub struct WfpEngine {
        handle: HANDLE,
        /// domain -> IPs claimed by that domain
        domain_ips: HashMap<String, Vec<[u8; 4]>>,
        /// ip -> (filter_id, refcount)
        ip_filters: HashMap<[u8; 4], (u64, usize)>,
    }

    // HANDLE is a raw pointer; engine is only used behind a Mutex on one service thread.
    unsafe impl Send for WfpEngine {}

    impl WfpEngine {
        pub fn open() -> Result<Self, String> {
            unsafe {
                let mut handle = HANDLE::default();
                // Explicit dynamic session: objects die with this process (no orphan blocks).
                let session_name = wide("A.T. Shield session");
                let mut session = FWPM_SESSION0::default();
                session.displayData.name = PWSTR(session_name.as_ptr() as *mut _);
                session.flags = FWPM_SESSION_FLAG_DYNAMIC;
                let status = FwpmEngineOpen0(
                    PCWSTR::null(),
                    RPC_C_AUTHN_WINNT,
                    None,
                    Some(&session),
                    &mut handle,
                );
                if status != ERROR_SUCCESS.0 {
                    return Err(format!("FwpmEngineOpen0 failed: 0x{status:X}"));
                }
                let mut eng = Self {
                    handle,
                    domain_ips: HashMap::new(),
                    ip_filters: HashMap::new(),
                };
                let _ = eng.ensure_provider();
                // Drop orphan filters from previous runs (esp. before DYNAMIC sessions).
                if let Err(e) = eng.purge_provider_filters() {
                    eprintln!("[at-shield] startup purge: {e}");
                }
                Ok(eng)
            }
        }

        fn ensure_provider(&mut self) -> Result<(), String> {
            unsafe {
                let name = wide("A.T. Shield");
                let desc = wide("Site blocking provider");
                let provider = FWPM_PROVIDER0 {
                    providerKey: PROVIDER_KEY,
                    displayData: FWPM_DISPLAY_DATA0 {
                        name: PWSTR(name.as_ptr() as *mut _),
                        description: PWSTR(desc.as_ptr() as *mut _),
                    },
                    flags: 0,
                    providerData: Default::default(),
                    serviceName: PWSTR::null(),
                };
                let status = FwpmProviderAdd0(self.handle, &provider, None);
                if status != ERROR_SUCCESS.0 && status != 0x80320009 {
                    eprintln!("[at-shield] FwpmProviderAdd0: 0x{status:X}");
                }
                Ok(())
            }
        }

        /// Delete every ATShield filter left in BFE (including persistent orphans).
        fn purge_provider_filters(&mut self) -> Result<(), String> {
            // Enum ALL filters (null template) — filtered enum templates were returning
            // FWP_E_INVALID_PARAMETER (0x80320004) and silently leaving orphans behind.
            let n = self.purge_all_atshield()?;
            eprintln!("[at-shield] purged {n} ATShield WFP filter(s)");
            self.domain_ips.clear();
            self.ip_filters.clear();
            Ok(())
        }

        fn purge_all_atshield(&self) -> Result<u32, String> {
            unsafe {
                let mut enum_handle = HANDLE::default();
                // NULL template = every filter in the system
                let status =
                    FwpmFilterCreateEnumHandle0(self.handle, None, &mut enum_handle);
                if status != ERROR_SUCCESS.0 {
                    return Err(format!("FwpmFilterCreateEnumHandle0 0x{status:X}"));
                }

                let mut deleted: u32 = 0;
                loop {
                    let mut entries: *mut *mut FWPM_FILTER0 = std::ptr::null_mut();
                    let mut n: u32 = 0;
                    let st = FwpmFilterEnum0(self.handle, enum_handle, 256, &mut entries, &mut n);
                    if st != ERROR_SUCCESS.0 || n == 0 {
                        break;
                    }
                    for i in 0..n as usize {
                        let f = &*(*entries.add(i));
                        let ours = (!f.providerKey.is_null()
                            && *f.providerKey == PROVIDER_KEY)
                            || filter_name_contains(f, "ATShield");
                        if ours
                            && FwpmFilterDeleteById0(self.handle, f.filterId) == ERROR_SUCCESS.0
                        {
                            deleted += 1;
                        }
                    }
                    let mut mem = entries as *mut std::ffi::c_void;
                    FwpmFreeMemory0(&mut mem);
                }
                let _ = FwpmFilterDestroyEnumHandle0(self.handle, enum_handle);
                Ok(deleted)
            }
        }

        pub fn block_domain(&mut self, domain: &str, subdomains: bool) -> Result<(), String> {
            self.unblock_domain(domain)?;
            let mut ips = resolve_ipv4(domain);
            if subdomains {
                for extra in resolve_ipv4(&format!("www.{domain}")) {
                    if !ips.contains(&extra) {
                        ips.push(extra);
                    }
                }
            }
            let mut claimed = Vec::new();
            for ip in ips {
                match self.acquire_ip(domain, ip) {
                    Ok(()) => claimed.push(ip),
                    Err(e) => eprintln!(
                        "[at-shield] filter {domain}/{}.{}.{}.{}: {e}",
                        ip[0], ip[1], ip[2], ip[3]
                    ),
                }
            }
            self.domain_ips.insert(domain.to_string(), claimed);
            Ok(())
        }

        fn acquire_ip(&mut self, domain: &str, ip: [u8; 4]) -> Result<(), String> {
            if let Some((_, count)) = self.ip_filters.get_mut(&ip) {
                *count += 1;
                return Ok(());
            }
            let id = self.add_block_ip(domain, ip)?;
            self.ip_filters.insert(ip, (id, 1));
            Ok(())
        }

        fn release_ip(&mut self, ip: [u8; 4]) {
            let Some((id, count)) = self.ip_filters.get_mut(&ip) else {
                return;
            };
            if *count > 1 {
                *count -= 1;
                return;
            }
            let id = *id;
            self.ip_filters.remove(&ip);
            unsafe {
                let _ = FwpmFilterDeleteById0(self.handle, id);
            }
        }

        fn add_block_ip(&self, domain: &str, ip: [u8; 4]) -> Result<u64, String> {
            unsafe {
                let name = wide(&format!("ATShield block {domain}"));
                let mut addr = FWP_V4_ADDR_AND_MASK {
                    addr: u32::from_be_bytes(ip),
                    mask: 0xFFFF_FFFF,
                };

                let mut condition = FWPM_FILTER_CONDITION0::default();
                condition.fieldKey = FWPM_CONDITION_IP_REMOTE_ADDRESS;
                condition.matchType = FWP_MATCH_EQUAL;
                condition.conditionValue.r#type = FWP_V4_ADDR_MASK;
                condition.conditionValue.Anonymous.v4AddrMask = &mut addr;

                let mut provider_key = PROVIDER_KEY;
                let mut filter = FWPM_FILTER0::default();
                filter.displayData.name = PWSTR(name.as_ptr() as *mut _);
                filter.flags = FWPM_FILTER_FLAGS(0);
                filter.providerKey = &mut provider_key;
                filter.layerKey = FWPM_LAYER_ALE_AUTH_CONNECT_V4;
                filter.numFilterConditions = 1;
                filter.filterCondition = &mut condition;
                filter.action.r#type = FWP_ACTION_BLOCK;

                let mut id: u64 = 0;
                let status = FwpmFilterAdd0(self.handle, &filter, None, Some(&mut id));
                if status != ERROR_SUCCESS.0 {
                    return Err(format!("FwpmFilterAdd0 0x{status:X}"));
                }
                Ok(id)
            }
        }

        pub fn unblock_domain(&mut self, domain: &str) -> Result<(), String> {
            if let Some(ips) = self.domain_ips.remove(domain) {
                for ip in ips {
                    self.release_ip(ip);
                }
            }
            Ok(())
        }

        pub fn clear(&mut self) -> Result<(), String> {
            // Full purge so disable/reapply never leaves QUIC-blocking orphans.
            self.purge_provider_filters()
        }
    }

    impl Drop for WfpEngine {
        fn drop(&mut self) {
            let _ = self.clear();
            unsafe {
                let _ = FwpmEngineClose0(self.handle);
            }
        }
    }

    fn wide(s: &str) -> Vec<u16> {
        s.encode_utf16().chain(std::iter::once(0)).collect()
    }

    fn filter_name_contains(f: &FWPM_FILTER0, needle: &str) -> bool {
        unsafe {
            let p = f.displayData.name.0;
            if p.is_null() {
                return false;
            }
            let mut len = 0usize;
            while *p.add(len) != 0 {
                len += 1;
                if len > 512 {
                    break;
                }
            }
            let s = String::from_utf16_lossy(std::slice::from_raw_parts(p, len));
            s.contains(needle)
        }
    }

    fn resolve_ipv4(domain: &str) -> Vec<[u8; 4]> {
        let host = format!("{domain}:0");
        match host.to_socket_addrs() {
            Ok(iter) => iter
                .filter_map(|a| match a {
                    std::net::SocketAddr::V4(v4) => Some(v4.ip().octets()),
                    _ => None,
                })
                .collect::<std::collections::HashSet<_>>()
                .into_iter()
                .collect(),
            Err(_) => Vec::new(),
        }
    }
}

#[cfg(windows)]
pub use win::WfpEngine;

#[cfg(not(windows))]
pub struct WfpEngine;

#[cfg(not(windows))]
impl WfpEngine {
    pub fn open() -> Result<Self, String> {
        Err("WFP only on Windows".into())
    }
    pub fn block_domain(&mut self, _: &str, _: bool) -> Result<(), String> {
        Ok(())
    }
    pub fn unblock_domain(&mut self, _: &str) -> Result<(), String> {
        Ok(())
    }
    pub fn clear(&mut self) -> Result<(), String> {
        Ok(())
    }
}
