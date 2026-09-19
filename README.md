<p align="center">
  <img src="apps/at_shield/assets/icon.png" alt="A.T. Shield Logo" width="120" />
  <br />
  <strong>A.T. Shield</strong>
</p>

<p align="center">
  System-level website blocker and focus tool built in Rust and Flutter.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License" /></a>
  <img src="https://img.shields.io/badge/platform-Windows%2010%2F11%20x64-0078D6" alt="Windows Support" />
  <img src="https://img.shields.io/badge/Linux%20%2F%20macOS-WIP-orange" alt="Linux and macOS WIP" />
  <img src="https://img.shields.io/badge/telemetry-none%20(offline)-green" alt="No Telemetry" />
</p>

---

## Overview

A.T. Shield is an open-source tool that blocks distracting websites across your entire system during timed focus sessions. It operates at the OS network level, so blocks apply to all browsers and applications without needing browser extensions.

Two blocking modes are supported per website:

1. **Hard Block**: Outbound connections to the domain are dropped immediately.
2. **Custom Page**: The domain is redirected to a local lightweight web server that displays a custom HTML page (such as the default campfire screen) directly in your browser.

<p align="center">
  <img src="docs/foco.webp" alt="A.T. Shield Focus Screen" width="620" />
  <br />
  <em>Default focus screen (<code>pages/foco.html</code>). Any custom HTML file can be configured per rule.</em>
</p>

---

## How Blocking Works

Here is a straightforward explanation of what happens under the hood when a focus session is active.

```
                    [ You open distracting.com ]
                                 |
              +------------------+------------------+
              |                                     |
    Mode: Hard Block                       Mode: Custom Page
              |                                     |
    Firewall drops the                    Redirects to 127.0.0.2
    connection at the OS                  Local web server returns
    network layer.                        your custom HTML page.
              |                                     |
              +------------------+------------------+
                                 |
                     [ Focus session ends ]
                                 |
              Rules and certificates are removed.
              Normal internet access is restored.
```

### 1. Hard Block Mode
When you try to load a blocked domain (e.g. `x.com`), your browser resolves the domain to an IP address and attempts to establish a TCP connection. A.T. Shield registers a rule with the operating system's native firewall (Windows Filtering Platform) to drop outbound packets to that IP. The connection terminates immediately before leaving your machine.

### 2. Custom Focus Page Mode
If you prefer seeing a focus reminder instead of a dead connection:

1. **Host redirection**: The domain is routed to `127.0.0.2` via the system `hosts` file.
2. **Local web server**: An embedded Rust web server running on `127.0.0.2:80` and `127.0.0.2:443` catches the request and serves the configured HTML page.
3. **HTTPS / HSTS handling**: Because modern websites strictly enforce HTTPS via HSTS, the background service generates a local self-signed certificate covering the blocked domains and trusts it in the system certificate store. This lets the browser display the local page cleanly without security warnings.

### 3. Session End & Fail-Safes
When the session timer completes or you manually stop the session:
- Firewall rules are dropped.
- The `hosts` file entries are cleared.
- Temporary certificates are removed from the certificate store.

If the UI crashes or the process is killed unexpectedly, an internal watchdog in the background service detects the loss of heartbeat and automatically removes all network blocks to prevent lockouts.

---

## Architecture & OS Support

The project is structured with a shared Rust core engine (`crates/at_shield_core`) and platform-specific network adapters.

| Operating System | Status | Implementation Details |
| :--- | :---: | :--- |
| **Windows** | **Fully supported (100%)** | Windows Service (`AtShieldService`) + Windows Filtering Platform (WFP) + `hosts` sync + dynamic TLS certificates. |
| **Linux** | **Planned (WIP)** | `systemd` daemon + `nftables`/`iptables` packet dropping + `/etc/hosts` redirection + system CA trust. |
| **macOS** | **Planned (WIP)** | `launchd` helper + Packet Filter (`PF` / `pfctl`) or NetworkExtension + `/etc/hosts` + Keychain trust. |
---

### Windows Implementation

On Windows 10/11 x64, A.T. Shield runs with a split-privilege design:

- **Desktop UI (`at_shield.exe`)**: Built with Flutter. Runs as a standard, unprivileged user.
- **Background Service (`AtShieldService`)**: Written in Rust. Runs under `LocalSystem` to manage network policies and communicates with the UI via Named Pipes (`\\.\pipe\at-shield`).

```
+-------------------------------------------------------------+
|                      FLUTTER UI                             |
|              (Standard unprivileged user)                   |
+-------------------------------------------------------------+
                              |
               Named Pipe (\\.\pipe\at-shield)
                              |
+-------------------------------------------------------------+
|               AT-SHIELD SERVICE (Rust / LocalSystem)         |
|                                                             |
|  +-----------------------+     +--------------------------+ |
|  |     WFP Controller    |     |    Page Server & TLS     | |
|  | (ALE_AUTH_CONNECT_V4) |     | (127.0.0.2:80 / 443)     | |
|  +-----------------------+     +--------------------------+ |
+-------------------------------------------------------------+
           |                                  |
   Outbound IPv4 Drop                 hosts file & certutil
```

Key technical details:
- **WFP dynamic sessions**: Hard blocks are added at `FWPM_LAYER_ALE_AUTH_CONNECT_V4` using `FWPM_SESSION_FLAG_DYNAMIC`. If the service process terminates, Windows automatically tears down all active dynamic filters.
- **Dedicated loopback IP (`127.0.0.2`)**: The sinkhole HTTP/HTTPS server binds specifically to `127.0.0.2` rather than `127.0.0.1`. This avoids conflicts with local development web servers running on `localhost`.
- **Certutil integration**: The sinkhole certificate is dynamically generated with `rcgen` and registered using Windows `certutil`. It is removed on session stop and on MSI uninstallation.

---

### Linux Implementation Plan

*Crate: [`crates/at_shield_linux`](file:///crates/at_shield_linux) (stub)*

- Daemon running under `systemd` (`at-shield.service`) communicating via Unix domain sockets (`/run/at-shield/engine.sock`).
- Hard blocking via `nftables` or `iptables` drop rules on the output chain.
- Custom page redirection via `/etc/hosts` and certificate trust managed via `update-ca-certificates`.

---

### macOS Implementation Plan

*Crate: [`crates/at_shield_macos`](file:///crates/at_shield_macos) (stub)*

- Privileged helper daemon managed by `launchd` (`com.nerd.at-shield.helper`).
- Hard blocking using Packet Filter (`PF` / `pfctl`) anchor rules or Apple's `NetworkExtension` framework (`NEFilterDataProvider`).
- Custom page redirection via `/etc/hosts` and certificate trust via `/usr/bin/security add-trusted-cert`.

---

## Security & Privacy

- **No telemetry**: 100% offline. No analytics, tracking, or network calls to external servers.
- **No kernel drivers**: Does not use `.sys` or `.kext` drivers, eliminating the risk of kernel crashes or BSODs.
- **No process injection**: Does not inspect memory, capture keystrokes, or hook into other running processes.
- **Clean uninstallation**: The MSI uninstaller stops the service, deletes all WFP rules, restores the `hosts` file, removes the sinkhole root certificate, and cleans up data directories.

> [!NOTE]
> **Anti-Cheat Notice**: Aggressive anti-cheat systems (such as Vanguard, EasyAntiCheat, BattlEye, or Faceit) monitor network and privilege changes. End any active focus session and stop the service before launching games protected by kernel-level anti-cheat software.

For additional security details, see [SECURITY.md](SECURITY.md).

---

## Installation (Windows)

1. Download the latest `ATShield-*.msi` from [Releases](https://github.com/vitor/at-shield/releases).
2. Run the MSI installer (requires Administrator approval once for the background service).
3. Launch **A.T. Shield** from the Start Menu.
4. Create a profile, add websites, select your blocking mode, and start a session.

---

## Development

### Requirements
- **Rust** (stable): [rustup.rs](https://rustup.rs)
- **Flutter SDK** (v3.12+): [flutter.dev](https://flutter.dev)
- **Visual Studio C++ Build Tools**
- **WiX Toolset v7** (for building the MSI): `winget install --id WiXToolset.WiXCLI -e`

### Running in Development Mode

To run both the service and the Flutter UI locally:

```bat
:: Option A: Run automated startup script
scripts\dev-windows.bat

:: Option B: Start manually in two terminals
:: Terminal 1: Background service (run terminal as Admin for network filtering)
cd crates\at_shield_service
cargo run -- --console

:: Terminal 2: Flutter UI
cd apps\at_shield
flutter pub get
flutter run -d windows
```

> **Page Preview**: While the service is running, preview the custom focus page in your browser at `http://127.0.0.1:47831/`.

### Emergency Unblock / Reset
If you interrupt a development session and need to force-clear any remaining rules:
```bat
:: Run as Administrator
scripts\nuke-blocks.bat
```
*(Or via Cargo: `cargo run -p at_shield_service -- --nuke`)*

### Building the MSI Installer

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-installer.ps1
```

The output installer will be placed at `dist\ATShield-1.0.0.msi`.

---

## Project Structure

```
at-shield/
├── apps/
│   └── at_shield/            # Flutter desktop application
├── packages/
│   └── at_shield_ui/         # UI theme and widget library
├── crates/
│   ├── at_shield_core/       # Core state engine, SQLite store, IPC types
│   ├── at_shield_service/    # Background daemon and Named Pipes server
│   ├── at_shield_windows/    # Windows WFP, hosts manager, TLS page server
│   ├── at_shield_linux/      # Linux adapter (roadmap stub)
│   ├── at_shield_macos/      # macOS adapter (roadmap stub)
│   ├── at_shield_android/    # Android FFI / VPN bindings (WIP)
│   └── at_shield_ffi/        # C / Dart FFI interface
├── pages/                    # Built-in HTML focus screens and assets
├── installer/                # WiX v7 installer source files
├── scripts/                  # Build and development scripts
└── docs/                     # Documentation media
```

---

## License

MIT License — see [LICENSE](LICENSE) for details.

