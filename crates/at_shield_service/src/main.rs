//! A.T. Shield background service — named pipe IPC, engine always warm.
//!
//! Run: `at-shield-service --console` for foreground dev.
//! Production: MSI registers this exe as Windows service `AtShieldService` (LocalSystem).

mod crashlog;
mod pipe;

use at_shield_core::{Engine, NoopFilter, Store};
use parking_lot::Mutex;
use std::path::PathBuf;
use std::sync::Arc;

fn data_dir() -> PathBuf {
    let base = std::env::var("PROGRAMDATA")
        .or_else(|_| std::env::var("LOCALAPPDATA"))
        .unwrap_or_else(|_| ".".into());
    PathBuf::from(base).join("ATShield")
}

fn pages_dir() -> PathBuf {
    let exe = std::env::current_exe().ok();
    if let Some(p) = exe.as_ref().and_then(|e| e.parent()) {
        let c = p.join("pages");
        if c.is_dir() {
            return c;
        }
    }
    PathBuf::from("pages")
}

fn build_engine() -> Result<Arc<Engine>, String> {
    let dir = data_dir();
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let store = Store::open(dir.join("shield.db"))?;
    #[cfg(windows)]
    let filter: Arc<dyn at_shield_core::NetworkFilter> = {
        match at_shield_windows::WindowsFilter::new(Some(pages_dir()), dir.join("certs")) {
            Ok(f) => Arc::new(f),
            Err(e) => {
                eprintln!("[at-shield] windows filter: {e}");
                Arc::new(NoopFilter::default())
            }
        }
    };
    #[cfg(not(windows))]
    let filter: Arc<dyn at_shield_core::NetworkFilter> = Arc::new(NoopFilter::default());
    Ok(Arc::new(Engine::new(store, filter)?))
}

fn run_console() -> Result<(), String> {
    let engine = build_engine()?;
    eprintln!(
        "[at-shield] service console — filter={} pipe={}",
        engine.filter_name(),
        at_shield_core::PIPE_NAME
    );
    engine.spawn_ui_watchdog();
    // ponytail: migrate + clear leftover hosts; blocks only on session start
    let warm = engine.clone();
    std::thread::spawn(move || {
        eprintln!("[at-shield] warming service (no blocks until session)...");
        match warm.warm_protection() {
            Ok(()) => eprintln!("[at-shield] ready"),
            Err(e) => eprintln!("[at-shield] warm failed: {e}"),
        }
    });
    pipe::serve_forever(engine)
}

fn main() {
    crashlog::init();

    let args: Vec<String> = std::env::args().collect();
    let console = args.iter().any(|a| a == "--console" || a == "-c");
    let nuke = args.iter().any(|a| a == "--nuke");
    let uninstall = args.iter().any(|a| a == "--uninstall-cleanup");

    if uninstall {
        #[cfg(windows)]
        {
            eprintln!("[at-shield] uninstall cleanup — WFP/hosts/cert/ProgramData...");
            match at_shield_windows::WindowsFilter::uninstall_cleanup() {
                Ok(()) => {
                    eprintln!("[at-shield] uninstall cleanup ok");
                    std::process::exit(0);
                }
                Err(e) => {
                    crashlog::fatal(&format!("uninstall cleanup falhou: {e}"));
                    std::process::exit(1);
                }
            }
        }
        #[cfg(not(windows))]
        {
            crashlog::fatal("uninstall-cleanup só no Windows");
            std::process::exit(1);
        }
    }

    if nuke {
        #[cfg(windows)]
        {
            eprintln!("[at-shield] NUKE — limpando WFP + hosts...");
            match at_shield_windows::WindowsFilter::nuke_all_blocks() {
                Ok(()) => {
                    eprintln!("[at-shield] NUKE ok — twitter/instagram devem voltar");
                    std::process::exit(0);
                }
                Err(e) => {
                    crashlog::fatal(&format!("NUKE falhou: {e}"));
                    std::process::exit(1);
                }
            }
        }
        #[cfg(not(windows))]
        {
            crashlog::fatal("nuke só no Windows");
            std::process::exit(1);
        }
    }

    if console || !cfg!(windows) {
        if let Err(e) = run_console() {
            crashlog::fatal(&format!("fatal: {e}"));
            std::process::exit(1);
        }
        return;
    }

    #[cfg(windows)]
    {
        // SCM dispatch when registered by the MSI; for local dev use --console.
        if let Err(e) = run_as_service() {
            crashlog::fatal(&format!("service dispatch failed ({e}), try --console"));
            std::process::exit(1);
        }
    }
}

#[cfg(windows)]
fn run_as_service() -> Result<(), String> {
    use std::ffi::OsString;
    use std::time::Duration;
    use windows_service::service::{
        ServiceControl, ServiceControlAccept, ServiceExitCode, ServiceState, ServiceStatus,
        ServiceType,
    };
    use windows_service::service_control_handler::{self, ServiceControlHandlerResult};
    use windows_service::{define_windows_service, service_dispatcher};

    const NAME: &str = "AtShieldService";

    define_windows_service!(ffi_service_main, service_main);

    fn service_main(_args: Vec<OsString>) {
        let stop = Arc::new(Mutex::new(false));
        let stop2 = stop.clone();
        let status_handle = service_control_handler::register(NAME, move |event| match event {
            ServiceControl::Stop => {
                *stop2.lock() = true;
                ServiceControlHandlerResult::NoError
            }
            ServiceControl::Interrogate => ServiceControlHandlerResult::NoError,
            _ => ServiceControlHandlerResult::NotImplemented,
        })
        .expect("register");

        let _ = status_handle.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Running,
            controls_accepted: ServiceControlAccept::STOP,
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        });

        match build_engine() {
            Ok(engine) => {
                engine.spawn_ui_watchdog();
                let warm = engine.clone();
                std::thread::spawn(move || {
                    let _ = warm.warm_protection();
                });
                let stop3 = stop.clone();
                let _ = std::thread::spawn(move || {
                    let _ = pipe::serve_forever_until(engine, move || *stop3.lock());
                });
                while !*stop.lock() {
                    std::thread::sleep(Duration::from_millis(400));
                }
            }
            Err(e) => crashlog::fatal(&format!("service build_engine failed: {e}")),
        }

        let _ = status_handle.set_service_status(ServiceStatus {
            service_type: ServiceType::OWN_PROCESS,
            current_state: ServiceState::Stopped,
            controls_accepted: ServiceControlAccept::empty(),
            exit_code: ServiceExitCode::Win32(0),
            checkpoint: 0,
            wait_hint: Duration::default(),
            process_id: None,
        });
    }

    service_dispatcher::start(NAME, ffi_service_main).map_err(|e| e.to_string())
}
