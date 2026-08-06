<p align="center">
  <img src="apps/at_shield/assets/icon.png" alt="Logo A.T. Shield" width="120" />
  <br />
  <strong>A.T. Shield</strong>
</p>

<p align="center">Bloqueador e redirecionador de sites, feito para sessões de foco.</p>

## Como funciona

Você escolhe os sites, cria um perfil e inicia uma sessão. Durante a sessão, o A.T. Shield bloqueia esses endereços e pode redirecionar para páginas personalizadas de conforto, afim de te relembrar do seu foco atual. Ao encerrar a sessão, o acesso volta ao normal.

Há duas opções:

- **Bloquear:** a conexão é interrompida.
- **Página personalizada:** a conexão é interrompida, porém redicionada o site mostra para página local, como a default do sistema `pages/foco.html`.

### A página de foco

Quando um site é bloqueado, você pode mostrar uma página tranquila para te relembrar do seu foco e sua determinação Abaixo temos o exemplo padrão do sistema, porém você pode configurar e carregar qualquer página html para ser sua página de foco/segurança:

<p align="center">
  <img src="docs/foco.webp" alt="Página de foco do A.T. Shield" width="560" />
</p>

## Segurança

O A.T. Shield para windows é open source e roda localmente. Com uma sessão ativa, o serviço usa recursos nativos do Windows:

- filtros de saída do **WFP** para bloquear conexões;
- uma entrada identificada no arquivo `hosts`, quando a página personalizada está ativa;
- servidores locais em `127.0.0.1` e `127.0.0.2`.

Ele não faz injeção em processos, não lê memória, não captura teclas ou telas, não instala driver de kernel e não envia seus dados para a nuvem.

O Windows pode alertar sobre builds sem assinatura Authenticode, e está explicado em [SECURITY.md](SECURITY.md).

## Como usar

**Requisito:** Windows 10/11 x64. O bloqueio de rede roda no serviço Windows (`AtShieldService`) com privilégios elevados; a interface abre como usuário normal.

### Instalação (recomendado)

1. Baixe o `ATShield-*.msi` da release (ou gere com `scripts\build-installer.ps1`).
2. Execute o MSI — o UAC pede admin **uma vez** (instalação per-machine).
3. Abra **A.T. Shield** pelo menu Iniciar.
4. Crie um perfil, adicione sites, escolha o modo de bloqueio e inicie a sessão.

Não é necessário instalar Rust, Flutter nem baixar crates no PC do usuário: o MSI já traz a UI, o serviço e as páginas.

Crashes/fatais do serviço vão para `C:\Program Files\AT Shield\logs\` (`crash-*.log` / `fatal-*.log`). Em dev (`--console`), o fallback é `%ProgramData%\ATShield\logs`.

Sem o serviço rodando (ou se ele não estiver elevado), a interface abre, mas o bloqueio de rede não é aplicado.

Antes de abrir jogos com Vanguard, EAC, BattlEye ou Faceit, encerre a sessão e pare o serviço (ou feche o app e use `services.msc`).

### Desinstalação

Remova pelo Painel de Controle / Configurações. O MSI para o serviço, limpa filtros WFP/`hosts`, remove o certificado sinkhole do store Root (se presente) e apaga `%ProgramData%\ATShield`.

## Para desenvolver

```bat 
:: atalho: scripts\dev-windows.bat (UI + serviço em --console)
:: ou manualmente:

:: terminal 1
cd crates\at_shield_service
cargo run -- --console

:: terminal 2
cd apps\at_shield
flutter pub get
flutter run -d windows
```

É necessário ter Flutter, Rust e o Visual Studio Build Tools com C++ instalados.

O preview das páginas fica em `http://127.0.0.1:47831/`.

### Gerar o MSI (máquina de build)

```powershell
winget install --id WiXToolset.WiXCLI -e
powershell -ExecutionPolicy Bypass -File scripts\build-installer.ps1
```

O script passa `-acceptEula wix7` (OSMF do WiX v7). Organizações com receita ≥ US$10k/ano devem seguir https://wixtoolset.org/osmf/.

Saída: `dist\ATShield-1.0.0.msi`.
Assinatura Authenticode opcional:

```powershell
$env:ATSHIELD_SIGN_THUMBPRINT = '<thumbprint do certificado>'
powershell -ExecutionPolicy Bypass -File scripts\build-installer.ps1
```

Detalhes de privilégios e SmartScreen: [SECURITY.md](SECURITY.md).
