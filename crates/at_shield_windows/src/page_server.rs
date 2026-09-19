//! Local page server for custom block pages.
//!
//! - :47831 preview on 127.0.0.1
//! - :80 / :443 sinkhole on 127.0.0.2 (hosts pins blocked domains there)
//!
//! ponytail: self-signed cert covering routed hostnames, installed into the Windows
//! Root store via certutil so HSTS/HTTPS sites (x.com etc.) render the custom page.
//! Ceiling: AV may flag Root CA install — upgrade path = EV signing / SignPath later.

use crate::hosts::SINKHOLE_IP;
use parking_lot::Mutex;
use rcgen::generate_simple_self_signed;
use rustls::pki_types::{CertificateDer, PrivateKeyDer, PrivatePkcs8KeyDer};
use rustls::server::{ResolvesServerCert, ServerConfig};
use rustls::sign::CertifiedKey;
use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread;
use tiny_http::{Header, Request, Response, Server, StatusCode};

pub struct PageServer {
    port: u16,
    routes: Arc<Mutex<HashMap<String, String>>>,
    /// Canonical domain → document navigation count (sinkhole only).
    hits: Arc<Mutex<HashMap<String, u32>>>,
    #[allow(dead_code)]
    root: PathBuf,
    cert_dir: PathBuf,
    tls: Arc<Mutex<Option<Arc<ServerConfig>>>>,
    _joins: Vec<thread::JoinHandle<()>>,
}

impl PageServer {
    pub fn start(root: PathBuf, cert_dir: PathBuf, preview_port: u16) -> Result<Self, String> {
        fs::create_dir_all(&cert_dir).map_err(|e| e.to_string())?;
        let routes: Arc<Mutex<HashMap<String, String>>> = Arc::new(Mutex::new(HashMap::new()));
        let hits: Arc<Mutex<HashMap<String, u32>>> = Arc::new(Mutex::new(HashMap::new()));
        let tls: Arc<Mutex<Option<Arc<ServerConfig>>>> = Arc::new(Mutex::new(None));
        let mut joins = Vec::new();

        {
            let root = root.clone();
            let routes = routes.clone();
            let server = Server::http(format!("127.0.0.1:{preview_port}")).map_err(|e| {
                format!("bind 127.0.0.1:{preview_port}: {e} — outra instancia ja rodando?")
            })?;
            joins.push(thread::spawn(move || {
                for request in server.incoming_requests() {
                    // preview — don't count as block attempts
                    handle_http(request, &root, &routes);
                }
            }));
        }

        match TcpListener::bind(format!("{SINKHOLE_IP}:80")) {
            Ok(listener) => {
                let root = root.clone();
                let routes = routes.clone();
                let hits = hits.clone();
                joins.push(thread::spawn(move || {
                    for stream in listener.incoming().flatten() {
                        let _ = handle_raw_http(stream, &root, &routes, &hits);
                    }
                }));
                eprintln!("[at-shield] sinkhole HTTP {SINKHOLE_IP}:80");
            }
            Err(e) => eprintln!("[at-shield] bind {SINKHOLE_IP}:80 failed ({e})"),
        }

        match TcpListener::bind(format!("{SINKHOLE_IP}:443")) {
            Ok(listener) => {
                let root = root.clone();
                let routes = routes.clone();
                let hits = hits.clone();
                let tls = tls.clone();
                joins.push(thread::spawn(move || {
                    for stream in listener.incoming().flatten() {
                        let cfg = tls.lock().clone();
                        let Some(cfg) = cfg else { continue };
                        let _ = handle_raw_https(stream, cfg, &root, &routes, &hits);
                    }
                }));
                eprintln!("[at-shield] sinkhole HTTPS {SINKHOLE_IP}:443");
            }
            Err(e) => eprintln!("[at-shield] bind {SINKHOLE_IP}:443 failed ({e})"),
        }

        let server = Self {
            port: preview_port,
            routes,
            hits,
            root,
            cert_dir,
            tls,
            _joins: joins,
        };
        server.refresh_tls();
        Ok(server)
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub fn set_route(&self, domain: &str, page_file: &str, include_subdomains: bool) {
        {
            let mut g = self.routes.lock();
            g.insert(domain.to_lowercase(), page_file.to_string());
            if include_subdomains {
                g.insert(
                    format!("www.{}", domain.to_lowercase()),
                    page_file.to_string(),
                );
            }
        }
        self.refresh_tls();
    }

    pub fn clear_route(&self, domain: &str) {
        {
            let mut g = self.routes.lock();
            g.remove(&domain.to_lowercase());
            g.remove(&format!("www.{}", domain.to_lowercase()));
        }
        self.refresh_tls();
    }

    pub fn clear_routes(&self) {
        self.routes.lock().clear();
        self.refresh_tls();
    }

    pub fn reset_hits(&self) {
        self.hits.lock().clear();
    }

    pub fn drain_hits(&self) -> Vec<(String, u32)> {
        let mut g = self.hits.lock();
        let mut out: Vec<_> = g.drain().collect();
        out.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        out
    }

    fn refresh_tls(&self) {
        match build_tls_config(&self.cert_dir, &self.routes) {
            Ok(cfg) => *self.tls.lock() = Some(cfg),
            Err(e) => eprintln!("[at-shield] tls refresh: {e}"),
        }
    }
}

fn handle_http(request: Request, root: &Path, routes: &Mutex<HashMap<String, String>>) {
    let host = request
        .headers()
        .iter()
        .find(|h| {
            h.field
                .as_str()
                .as_str()
                .eq_ignore_ascii_case("Host")
        })
        .map(|h| h.value.as_str().to_string())
        .unwrap_or_default();
    let host = host.split(':').next().unwrap_or("").to_lowercase();
    let url = request.url().to_string();
    let body_path = resolve_path(root, routes, &host, &url);
    let resp = match body_path.and_then(|p| fs::read(&p).ok()) {
        Some(body) => {
            let ctype = content_type(&url);
            let mut r = Response::from_data(body);
            if let Ok(h) = Header::from_bytes("Content-Type", ctype) {
                r.add_header(h);
            }
            r
        }
        None => Response::from_string("A.T. Shield — página não encontrada")
            .with_status_code(StatusCode(404)),
    };
    let _ = request.respond(resp);
}

fn handle_raw_http(
    mut stream: TcpStream,
    root: &Path,
    routes: &Mutex<HashMap<String, String>>,
    hits: &Mutex<HashMap<String, u32>>,
) -> Result<(), String> {
    let mut buf = [0u8; 8192];
    let n = stream.read(&mut buf).map_err(|e| e.to_string())?;
    if n == 0 {
        return Ok(());
    }
    let req = String::from_utf8_lossy(&buf[..n]);
    let (path, host) = parse_request(&req);
    record_document_hit(routes, hits, &host, &path);
    let file = resolve_path(root, routes, &host, &path);
    write_http_response(&mut stream, &path, file)
}

fn handle_raw_https(
    stream: TcpStream,
    config: Arc<ServerConfig>,
    root: &Path,
    routes: &Mutex<HashMap<String, String>>,
    hits: &Mutex<HashMap<String, u32>>,
) -> Result<(), String> {
    let conn = rustls::ServerConnection::new(config).map_err(|e| format!("tls conn: {e}"))?;
    let mut tls = rustls::StreamOwned::new(conn, stream);
    let mut buf = [0u8; 8192];
    let n = tls.read(&mut buf).map_err(|e| e.to_string())?;
    if n == 0 {
        return Ok(());
    }
    let req = String::from_utf8_lossy(&buf[..n]);
    let (path, host) = parse_request(&req);
    record_document_hit(routes, hits, &host, &path);
    let file = resolve_path(root, routes, &host, &path);
    write_http_response(&mut tls, &path, file)
}

/// Count one attempt per HTML document navigation (skip css/js/favicon).
fn record_document_hit(
    routes: &Mutex<HashMap<String, String>>,
    hits: &Mutex<HashMap<String, u32>>,
    host: &str,
    path: &str,
) {
    if host.is_empty() {
        return;
    }
    if !is_document_path(path) {
        return;
    }
    let host_l = host.to_lowercase();
    let routed = {
        let g = routes.lock();
        g.contains_key(&host_l)
    };
    if !routed {
        return;
    }
    let domain = host_l
        .strip_prefix("www.")
        .unwrap_or(host_l.as_str())
        .to_string();
    *hits.lock().entry(domain).or_insert(0) += 1;
}

fn is_document_path(path: &str) -> bool {
    let path = path.split('?').next().unwrap_or(path);
    if path == "/" || path.is_empty() {
        return true;
    }
    let lower = path.to_lowercase();
    if lower.ends_with(".html") || lower.ends_with(".htm") {
        return true;
    }
    // path with no extension → treat as document
    let name = path.rsplit('/').next().unwrap_or(path);
    !name.contains('.')
}

fn write_http_response(
    w: &mut impl Write,
    url_path: &str,
    file: Option<PathBuf>,
) -> Result<(), String> {
    match file.and_then(|p| fs::read(p).ok()) {
        Some(body) => {
            let ctype = content_type(url_path);
            let header = format!(
                "HTTP/1.1 200 OK\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            );
            w.write_all(header.as_bytes()).map_err(|e| e.to_string())?;
            w.write_all(&body).map_err(|e| e.to_string())?;
        }
        None => {
            let body = b"A.T. Shield - pagina nao encontrada";
            let header = format!(
                "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                body.len()
            );
            w.write_all(header.as_bytes()).map_err(|e| e.to_string())?;
            w.write_all(body).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

fn parse_request(req: &str) -> (String, String) {
    let mut path = "/".to_string();
    let mut host = String::new();
    for (i, line) in req.lines().enumerate() {
        if i == 0 {
            let mut parts = line.split_whitespace();
            let _method = parts.next();
            if let Some(p) = parts.next() {
                path = p.split('?').next().unwrap_or("/").to_string();
            }
            continue;
        }
        if line.is_empty() {
            break;
        }
        if let Some(rest) = line
            .strip_prefix("Host:")
            .or_else(|| line.strip_prefix("host:"))
        {
            host = rest.trim().split(':').next().unwrap_or("").to_lowercase();
        }
    }
    (path, host)
}

fn resolve_path(
    root: &Path,
    routes: &Mutex<HashMap<String, String>>,
    host: &str,
    url: &str,
) -> Option<PathBuf> {
    let rel = url.trim_start_matches('/').split('?').next().unwrap_or("");
    if !rel.is_empty() && rel.contains('.') {
        if let Some(rest) = rel.strip_prefix("pages/") {
            if let Some(p) = existing_under(root, rest) {
                return Some(p);
            }
        } else if let Some(p) = existing_under(root, rel) {
            return Some(p);
        }
        // css/js next to an absolute HTML route
        if let Some(page) = routes.lock().get(host).cloned() {
            if let Some(base) = absolute_page_parent(&page) {
                if let Some(p) = existing_under(&base, rel) {
                    return Some(p);
                }
            }
        }
    }
    // Unknown Host → 404. Never serve a block page for localhost / lvh.me / etc.
    let page = routes.lock().get(host).cloned()?;
    resolve_page_file(root, &page)
}

/// Filename under `pages/`, or absolute path to a `.html` / `.htm` file.
fn resolve_page_file(root: &Path, page: &str) -> Option<PathBuf> {
    let p = PathBuf::from(page);
    if p.is_absolute() {
        return absolute_html(&p);
    }
    existing_under(root, page)
}

fn absolute_html(p: &Path) -> Option<PathBuf> {
    let ext = p.extension()?.to_str()?;
    if !ext.eq_ignore_ascii_case("html") && !ext.eq_ignore_ascii_case("htm") {
        return None;
    }
    if !p.is_file() {
        return None;
    }
    p.canonicalize().ok()
}

fn absolute_page_parent(page: &str) -> Option<PathBuf> {
    let p = PathBuf::from(page);
    if !p.is_absolute() {
        return None;
    }
    absolute_html(&p)?.parent().map(|x| x.to_path_buf())
}

fn existing_under(base: &Path, rel: &str) -> Option<PathBuf> {
    let rel_path = Path::new(rel);
    if rel_path.is_absolute() {
        return None;
    }
    let p = base.join(rel_path);
    if !p.exists() {
        return None;
    }
    let canon_base = base.canonicalize().ok()?;
    let canon = p.canonicalize().ok()?;
    if canon.starts_with(&canon_base) {
        Some(canon)
    } else {
        None
    }
}

fn content_type(url: &str) -> &'static str {
    let path = url.split('?').next().unwrap_or(url);
    if path.ends_with(".css") {
        "text/css; charset=utf-8"
    } else if path.ends_with(".js") {
        "application/javascript; charset=utf-8"
    } else if path.ends_with(".png") {
        "image/png"
    } else if path.ends_with(".svg") {
        "image/svg+xml"
    } else {
        "text/html; charset=utf-8"
    }
}

fn build_tls_config(
    cert_dir: &Path,
    routes: &Mutex<HashMap<String, String>>,
) -> Result<Arc<ServerConfig>, String> {
    let mut names: Vec<String> = routes.lock().keys().cloned().collect();
    names.sort();
    if names.is_empty() {
        names.push("localhost".into());
    }

    let stamped = cert_dir.join("sinkhole.names");
    let cert_path = cert_dir.join("sinkhole.cer");
    let key_path = cert_dir.join("sinkhole.key.pem");
    let names_blob = names.join("\n");
    let reuse = stamped
        .exists()
        .then(|| fs::read_to_string(&stamped).ok())
        .flatten()
        .is_some_and(|s| s == names_blob)
        && cert_path.exists()
        && key_path.exists();

    let (cert_der, key_pem) = if reuse {
        (
            fs::read(&cert_path).map_err(|e| e.to_string())?,
            fs::read_to_string(&key_path).map_err(|e| e.to_string())?,
        )
    } else {
        let certified =
            generate_simple_self_signed(names.clone()).map_err(|e| format!("rcgen: {e}"))?;
        let der = certified.cert.der().to_vec();
        let key = certified.key_pair.serialize_pem();
        fs::write(&cert_path, &der).map_err(|e| e.to_string())?;
        fs::write(&key_path, &key).map_err(|e| e.to_string())?;
        fs::write(&stamped, &names_blob).map_err(|e| e.to_string())?;
        (der, key)
    };
    // Always (re)trust — reuse path still needs Root if cert was written without install.
    install_ca_trust(&cert_path);

    let key_pair = rcgen::KeyPair::from_pem(&key_pem).map_err(|e| format!("key: {e}"))?;
    let key_der = PrivateKeyDer::Pkcs8(PrivatePkcs8KeyDer::from(key_pair.serialize_der()));
    let cert = CertificateDer::from(cert_der);

    let _ = rustls::crypto::ring::default_provider().install_default();
    let provider = rustls::crypto::ring::default_provider();
    let signing = provider
        .key_provider
        .load_private_key(key_der)
        .map_err(|e| format!("load key: {e}"))?;
    let ck = CertifiedKey::new(vec![cert], signing);

    let mut config = ServerConfig::builder()
        .with_no_client_auth()
        .with_cert_resolver(Arc::new(StaticCert(Arc::new(ck))));
    config.alpn_protocols = vec![b"http/1.1".to_vec()];
    Ok(Arc::new(config))
}

#[derive(Debug)]
struct StaticCert(Arc<CertifiedKey>);

impl ResolvesServerCert for StaticCert {
    fn resolve(&self, _client_hello: rustls::server::ClientHello<'_>) -> Option<Arc<CertifiedKey>> {
        Some(self.0.clone())
    }
}

fn install_ca_trust(cer: &Path) {
    match std::process::Command::new("certutil")
        .args(["-addstore", "-f", "Root"])
        .arg(cer)
        .output()
    {
        Ok(o) if o.status.success() => {
            eprintln!("[at-shield] sinkhole cert trusted in Root store");
        }
        Ok(o) => eprintln!(
            "[at-shield] certutil: {}",
            String::from_utf8_lossy(&o.stderr)
        ),
        Err(e) => eprintln!("[at-shield] certutil: {e}"),
    }
}

/// Remove the sinkhole cert from LocalMachine\Root (MSI uninstall / --uninstall-cleanup).
/// Matches by thumbprint of the on-disk `.cer` so we don't wipe unrelated roots.
pub fn remove_ca_trust(cer: &Path) {
    if !cer.is_file() {
        return;
    }
    let path = cer.to_string_lossy().replace('\'', "''");
    let script = format!(
        "$ErrorActionPreference='Stop'; \
         $cer = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2('{path}'); \
         $store = New-Object System.Security.Cryptography.X509Certificates.X509Store('Root','LocalMachine'); \
         $store.Open('ReadWrite'); \
         $store.Certificates | Where-Object {{ $_.Thumbprint -eq $cer.Thumbprint }} | ForEach-Object {{ [void]$store.Remove($_) }}; \
         $store.Close();"
    );
    match std::process::Command::new("powershell.exe")
        .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", &script])
        .output()
    {
        Ok(o) if o.status.success() => {
            eprintln!("[at-shield] sinkhole cert removed from Root store");
        }
        Ok(o) => eprintln!(
            "[at-shield] remove Root cert: {}",
            String::from_utf8_lossy(&o.stderr)
        ),
        Err(e) => eprintln!("[at-shield] remove Root cert: {e}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

    #[test]
    fn resolve_page_file_accepts_absolute_html() {
        let dir = std::env::temp_dir().join("at-shield-page-abs-test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let html = dir.join("tela.html");
        let css = dir.join("style.css");
        fs::write(&html, "<h1>ok</h1>").unwrap();
        fs::write(&css, "body{}").unwrap();
        let root = dir.join("pages");
        fs::create_dir_all(&root).unwrap();

        let got = resolve_page_file(&root, html.to_str().unwrap()).unwrap();
        assert_eq!(got, html.canonicalize().unwrap());

        assert!(resolve_page_file(&root, css.to_str().unwrap()).is_none());
        assert!(resolve_page_file(&root, "missing.html").is_none());

        let parent = absolute_page_parent(html.to_str().unwrap()).unwrap();
        let sibling = existing_under(&parent, "style.css").unwrap();
        assert_eq!(sibling, css.canonicalize().unwrap());

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn remove_ca_trust_missing_file_is_noop() {
        remove_ca_trust(Path::new(
            r"C:\this\path\should\not\exist\at-shield-sinkhole.cer",
        ));
    }

    #[test]
    fn unknown_host_does_not_get_foco() {
        let dir = std::env::temp_dir().join("at-shield-page-host-test");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("foco.html"), "<h1>foco</h1>").unwrap();
        fs::write(dir.join("detox.html"), "<h1>detox</h1>").unwrap();

        let routes = Mutex::new(HashMap::from([(
            "x.com".to_string(),
            "detox.html".to_string(),
        )]));

        let known = resolve_path(&dir, &routes, "x.com", "/").unwrap();
        assert!(known.ends_with("detox.html"));

        assert!(resolve_path(&dir, &routes, "lcl.lvh.me", "/").is_none());
        assert!(resolve_path(&dir, &routes, "localhost", "/").is_none());

        let _ = fs::remove_dir_all(&dir);
    }
}
