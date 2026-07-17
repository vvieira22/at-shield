//! Length-prefixed JSON over Windows named pipe (or TCP 127.0.0.1:47830 fallback).
//! Protocol: u32 LE length + UTF-8 JSON request → u32 LE length + UTF-8 JSON response.

use at_shield_core::{Engine, PIPE_NAME};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::thread;

pub fn serve_forever(engine: Arc<Engine>) -> Result<(), String> {
    serve_forever_until(engine, || false)
}

pub fn serve_forever_until<F>(engine: Arc<Engine>, mut should_stop: F) -> Result<(), String>
where
    F: FnMut() -> bool + Send + 'static,
{
    // ponytail: named pipe APIs are awkward cross-crate; TCP loopback is equally local,
    // instant, and trivial from Dart. Pipe name kept as logical ID; bind TCP 47830.
    let _ = PIPE_NAME;
    let listener = TcpListener::bind("127.0.0.1:47830").map_err(|e| {
        format!(
            "porta 47830 ocupada ({e}). Feche o outro at-shield-service (taskkill /F /IM at-shield-service.exe) e tente de novo"
        )
    })?;
    listener
        .set_nonblocking(true)
        .map_err(|e| e.to_string())?;
    eprintln!("[at-shield] IPC listening on 127.0.0.1:47830");

    while !should_stop() {
        match listener.accept() {
            Ok((stream, _)) => {
                let eng = engine.clone();
                thread::spawn(move || {
                    if let Err(e) = handle_client(stream, eng) {
                        eprintln!("[at-shield] client: {e}");
                    }
                });
            }
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(std::time::Duration::from_millis(50));
            }
            Err(e) => return Err(e.to_string()),
        }
    }
    Ok(())
}

fn handle_client(mut stream: TcpStream, engine: Arc<Engine>) -> Result<(), String> {
    stream
        .set_read_timeout(Some(std::time::Duration::from_secs(30)))
        .ok();
    loop {
        let mut len_buf = [0u8; 4];
        if stream.read_exact(&mut len_buf).is_err() {
            break;
        }
        let len = u32::from_le_bytes(len_buf) as usize;
        if len == 0 || len > 8 * 1024 * 1024 {
            break;
        }
        let mut body = vec![0u8; len];
        stream.read_exact(&mut body).map_err(|e| e.to_string())?;
        let req = String::from_utf8_lossy(&body);
        let resp = engine.handle_json(&req);
        let bytes = resp.as_bytes();
        let rlen = (bytes.len() as u32).to_le_bytes();
        stream.write_all(&rlen).map_err(|e| e.to_string())?;
        stream.write_all(bytes).map_err(|e| e.to_string())?;
        stream.flush().ok();
    }
    Ok(())
}
