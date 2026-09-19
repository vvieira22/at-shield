# Security

## Reportar

Abra uma issue no repositório descrevendo o problema (sem incluir dados sensíveis desnecessários). Para vulnerabilidades que não devam ser públicas de imediato, descreva o impacto e um contato preferido na issue e marque como segurança se o GitHub do repo permitir private reporting.

## Comportamentos privilegiados (Windows)

Com o serviço instalado pelo MSI (`AtShieldService`, conta **LocalSystem**) e uma sessão de foco ativa, o A.T. Shield pode:

| Ação | Quando |
|------|--------|
| Abrir engine WFP e adicionar filtros BLOCK outbound (IPv4) | Modo **Bloquear** |
| Escrever bloco marcado em `C:\Windows\System32\drivers\etc\hosts` | Modo **Página personalizada** |
| Bind em `127.0.0.2:80` e `:443` (sinkhole) | Serviço iniciado (serve só com hosts ativo) |
| IPC em `127.0.0.1:47830` e preview em `127.0.0.1:47831` | Sempre que o serviço roda |
| Instalar cert self-signed no store **Root** (LocalMachine) | Sinkhole HTTPS / HSTS |

A **UI** (`at_shield.exe`) não precisa de Admin. O UAC aparece na **instalação** do MSI (per-machine). Em desenvolvimento sem MSI, rode `at-shield-service.exe --console` como Administrador.

Sem o serviço elevado: UI e tracking funcionam; bloqueio de rede não.

Na desinstalação, o MSI chama `at-shield-service.exe --uninstall-cleanup` (WFP/`hosts`/cert Root/ `%ProgramData%\ATShield`).

## O que não fazemos

- Sem process injection, hooks de teclado/mouse, drivers `.sys`, Npcap/WinDivert, screenshot ou leitura de memória de outros processos.

## Certificado Root (página personalizada HTTPS)

Para sites HTTPS/HSTS (ex.: x.com) mostrarem a página HTML local, o serviço instala um certificado self-signed no **Windows Root store** via `certutil -addstore Root` (só enquanto o sinkhole TLS é montado). Isso é necessário para o browser aceitar a página de foco; antivírus pode flagar esse comportamento.

Sem essa instalação, o site ainda é redirecionado via `hosts`, mas o browser mostra erro de certificado.

## Code signing

O script `scripts\build-installer.ps1` assina `at_shield.exe`, `at-shield-service.exe` e o `.msi` quando `ATSHIELD_SIGN_THUMBPRINT` (ou `-SignThumbprint`) aponta para um certificado Authenticode instalado e o Windows SDK `signtool` está no PATH.

Sem thumbprint, o artefato é **unsigned (beta)** — SmartScreen/Defender podem alertar até haver reputação ou assinatura. Submissão de falso positivo: https://www.microsoft.com/en-us/wdsi/filesubmission

Assinatura Authenticode gratuita para OSS via [SignPath Foundation](https://signpath.org/) permanece no roadmap (após repo público + releases estáveis).

## Anti-cheat

Filtros de rede + processo elevado podem conflitar com Vanguard, EasyAntiCheat, BattlEye e Faceit. Encerre a sessão e o serviço antes de abrir esses jogos. Não há allowlist pública para este tipo de app.
