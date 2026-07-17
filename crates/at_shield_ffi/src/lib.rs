//! FFI + optional in-process engine for Flutter / pipe client helpers.

use at_shield_core::{Engine, NoopFilter, Store, PIPE_NAME};
use parking_lot::Mutex;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::Arc;

static ENGINE: Mutex<Option<Arc<Engine>>> = Mutex::new(None);

fn default_db_path() -> PathBuf {
    let base = std::env::var("LOCALAPPDATA")
        .or_else(|_| std::env::var("HOME"))
        .unwrap_or_else(|_| ".".into());
    PathBuf::from(base)
        .join("ATShield")
        .join("shield.db")
}

fn default_pages_dir() -> PathBuf {
    // prefer sibling pages/ from cwd / exe
    let candidates = [
        PathBuf::from("pages"),
        PathBuf::from("../pages"),
        PathBuf::from("../../pages"),
    ];
    for c in candidates {
        if c.is_dir() {
            return c;
        }
    }
    PathBuf::from("pages")
}

/// Start in-process engine (dev / fallback when service is down).
#[no_mangle]
pub extern "C" fn at_shield_engine_start() -> i32 {
    let mut g = ENGINE.lock();
    if g.is_some() {
        return 0;
    }
    let store = match Store::open(default_db_path()) {
        Ok(s) => s,
        Err(_) => return -1,
    };
    #[cfg(windows)]
    let filter: Arc<dyn at_shield_core::NetworkFilter> = {
        match at_shield_windows::WindowsFilter::new(Some(default_pages_dir())) {
            Ok(f) => Arc::new(f),
            Err(_) => Arc::new(NoopFilter::default()),
        }
    };
    #[cfg(not(windows))]
    let filter: Arc<dyn at_shield_core::NetworkFilter> = Arc::new(NoopFilter::default());

    match Engine::new(store, filter) {
        Ok(e) => {
            let eng = Arc::new(e);
            let warm = eng.clone();
            std::thread::spawn(move || {
                let _ = warm.warm_protection();
            });
            *g = Some(eng);
            0
        }
        Err(_) => -2,
    }
}

#[no_mangle]
pub extern "C" fn at_shield_engine_stop() {
    *ENGINE.lock() = None;
}

/// JSON command → heap-allocated C string (caller frees with at_shield_string_free).
#[no_mangle]
pub extern "C" fn at_shield_rpc(request_json: *const c_char) -> *mut c_char {
    if request_json.is_null() {
        return CString::new(r#"{"ok":"error","data":{"message":"null request"}}"#)
            .unwrap()
            .into_raw();
    }
    let req = unsafe { CStr::from_ptr(request_json) }.to_string_lossy();

    // Prefer live engine; auto-start if needed
    if ENGINE.lock().is_none() {
        let _ = at_shield_engine_start();
    }
    let out = if let Some(eng) = ENGINE.lock().as_ref() {
        eng.handle_json(&req)
    } else {
        r#"{"ok":"error","data":{"message":"engine not started"}}"#.to_string()
    };
    CString::new(out).unwrap_or_default().into_raw()
}

#[no_mangle]
pub extern "C" fn at_shield_string_free(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(ptr));
    }
}

#[no_mangle]
pub extern "C" fn at_shield_pipe_name() -> *mut c_char {
    CString::new(PIPE_NAME).unwrap().into_raw()
}
