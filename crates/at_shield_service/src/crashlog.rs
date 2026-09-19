//! Crash / fatal file logs next to the installed service (`logs\`).
//!
//! Prefer `<exe_dir>\logs` (MSI creates it). Fall back to `%ProgramData%\ATShield\logs`
//! when the install dir is missing or not writable (dev `--console`).

use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

static LOGS_DIR: OnceLock<PathBuf> = OnceLock::new();

pub fn init() {
    let dir = resolve_logs_dir();
    let _ = fs::create_dir_all(&dir);
    let _ = LOGS_DIR.set(dir);
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = write_named("crash", &format!("{info}\n"));
        prev(info);
    }));
}

pub fn fatal(msg: &str) {
    let _ = write_named("fatal", &format!("{msg}\n"));
    eprintln!("[at-shield] {msg}");
}

fn resolve_logs_dir() -> PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            let beside = parent.join("logs");
            if beside.is_dir() || fs::create_dir_all(&beside).is_ok() {
                return beside;
            }
        }
    }
    let base = std::env::var("PROGRAMDATA")
        .or_else(|_| std::env::var("LOCALAPPDATA"))
        .unwrap_or_else(|_| ".".into());
    PathBuf::from(base).join("ATShield").join("logs")
}

fn logs_dir() -> PathBuf {
    LOGS_DIR.get().cloned().unwrap_or_else(resolve_logs_dir)
}

fn stamp() -> String {
    // ponytail: unix stamp is enough for unique crash files; upgrade to local datetime if needed
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("{secs}")
}

fn write_named(kind: &str, body: &str) -> std::io::Result<()> {
    let dir = logs_dir();
    fs::create_dir_all(&dir)?;
    let path = dir.join(format!("{kind}-{}.log", stamp()));
    write_file(&path, kind, body)
}

fn write_file(path: &Path, kind: &str, body: &str) -> std::io::Result<()> {
    let mut f = OpenOptions::new().create(true).append(true).open(path)?;
    writeln!(f, "=== at-shield {kind} pid={} ===", std::process::id())?;
    f.write_all(body.as_bytes())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn write_file_creates_crash_log() {
        let dir = std::env::temp_dir().join(format!("atshield-crashlog-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let path = dir.join("crash-test.log");
        write_file(&path, "crash", "boom\n").unwrap();
        let text = fs::read_to_string(&path).unwrap();
        assert!(text.contains("boom"), "{text}");
        assert!(text.contains("at-shield crash"), "{text}");
        let _ = fs::remove_dir_all(&dir);
    }
}
