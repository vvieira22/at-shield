//! Pin blocked domains to 127.0.0.1 via the Windows hosts file.
//!
//! ponytail: only used for RedirectTarget::CustomPage so the local page server
//! can answer. Hard-block mode stays on WFP (no hosts). Ceiling = hosts is
//! easy to edit by hand; upgrade path = driver/MITM if we need tamper-resistance.

use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;

const BEGIN: &str = "# BEGIN AT_SHIELD";
const END: &str = "# END AT_SHIELD";

fn hosts_path() -> PathBuf {
    PathBuf::from(r"C:\Windows\System32\drivers\etc\hosts")
}

/// Replace our marked block with `lines` (each already "127.0.0.1 domain").
pub fn rewrite(entries: &[String]) -> Result<(), String> {
    let path = hosts_path();
    let mut raw = String::new();
    {
        let mut f = fs::OpenOptions::new()
            .read(true)
            .open(&path)
            .map_err(|e| format!("open hosts: {e}"))?;
        f.read_to_string(&mut raw)
            .map_err(|e| format!("read hosts: {e}"))?;
    }

    let mut out = String::new();
    let mut skipping = false;
    for line in raw.lines() {
        let t = line.trim();
        if t == BEGIN {
            skipping = true;
            continue;
        }
        if t == END {
            skipping = false;
            continue;
        }
        if !skipping {
            out.push_str(line);
            out.push('\n');
        }
    }
    if !out.ends_with('\n') && !out.is_empty() {
        out.push('\n');
    }
    if !entries.is_empty() {
        out.push_str(BEGIN);
        out.push('\n');
        for e in entries {
            out.push_str(e);
            out.push('\n');
        }
        out.push_str(END);
        out.push('\n');
    }

    // Write via temp + rename is nicer, but hosts often needs in-place truncate.
    let mut f = fs::OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(&path)
        .map_err(|e| format!("write hosts (precisa admin): {e}"))?;
    f.write_all(out.as_bytes())
        .map_err(|e| format!("write hosts: {e}"))?;
    // Make browsers/OS pick up the new mapping immediately.
    let _ = std::process::Command::new("ipconfig")
        .args(["/flushdns"])
        .output();
    Ok(())
}

pub fn clear() -> Result<(), String> {
    rewrite(&[])
}

/// Build hosts lines for a domain (+ www if subdomains).
pub fn lines_for(domain: &str, include_subdomains: bool) -> Vec<String> {
    let mut v = vec![format!("127.0.0.1 {domain}")];
    if include_subdomains {
        v.push(format!("127.0.0.1 www.{domain}"));
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lines_include_www() {
        let l = lines_for("x.com", true);
        assert!(l.iter().any(|s| s.contains("www.x.com")));
    }
}
