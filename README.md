# A.T. Shield

Bloqueador de sites leve e rápido. Flutter UI + Rust engine.

- **Bloquear** → WFP (IP drop)
- **Página personalizada** → `hosts` → 127.0.0.1 + HTML local (`pages/`)

## Arquitetura

```
Flutter UI  →  TCP 127.0.0.1:47830  →  at-shield-service (Rust)
                                         ├─ at_shield_core (regras em memória + SQLite)
                                         └─ at_shield_windows (WFP + páginas em :47831)
```

Adapters stub: Android (VpnService depois), Linux, macOS. Core único — sem branch por OS.

## Dev rápido (Windows)

```bat
:: terminal 1 — serviço (engine quente)
cd crates\at_shield_service
cargo run -- --console

:: terminal 2 — UI
cd apps\at_shield
flutter pub get
flutter run -d windows
```

Precisa do Visual Studio Build Tools (C++) para `cargo` e Flutter Windows.

## Comandos IPC (JSON)

- `{"cmd":"health"}`
- `{"cmd":"list_sites","profile_id":"profile-trabalho"}`
- `{"cmd":"set_enabled","id":"...","enabled":false}`
- `{"cmd":"set_enabled_batch","ids":["..."],"enabled":true}`
- `{"cmd":"start_session","profile_id":"...","duration_secs":2700}`

## Páginas custom

Pasta `pages/` — preview em `http://127.0.0.1:47831/`.

Com **Redirecionar → Página personalizada**, o serviço escreve o domínio no `hosts` (`127.0.0.1`) e serve o HTML em `:80`/`:443` (certificado local instalado no Root). Precisa **Admin**.

Com **Bloquear**, usa só WFP (derruba a conexão, sem HTML).

## WFP / hosts

O serviço precisa de elevação (UAC): WFP, `hosts`, e bind nas portas 80/443. Sem admin, fica em modo tracking (UI funciona, rede não).
