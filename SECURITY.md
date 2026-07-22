# Security

## Reportar

Abra uma issue no repositório descrevendo o problema (sem incluir dados sensíveis desnecessários). Para vulnerabilidades que não devam ser públicas de imediato, descreva o impacto e um contato preferido na issue e marque como segurança se o GitHub do repo permitir private reporting.

## Comportamentos privilegiados (Windows)

Com o serviço elevado (Admin) e uma sessão de foco ativa, o A.T. Shield pode:

| Ação | Quando |
|------|--------|
| Abrir engine WFP e adicionar filtros BLOCK outbound (IPv4) | Modo **Bloquear** |
| Escrever bloco marcado em `C:\Windows\System32\drivers\etc\hosts` | Modo **Página personalizada** |
| Bind em `127.0.0.2:80` e `:443` (sinkhole) | Serviço iniciado (serve só com hosts ativo) |
| IPC em `127.0.0.1:47830` e preview em `127.0.0.1:47831` | Sempre que o serviço roda |

Sem Admin: UI e tracking funcionam; bloqueio de rede não.

## O que não fazemos

- Sem process injection, hooks de teclado/mouse, drivers `.sys`, Npcap/WinDivert, screenshot ou leitura de memória de outros processos.

## Certificado Root (página personalizada HTTPS)

Para sites HTTPS/HSTS (ex.: x.com) mostrarem a página HTML local, o serviço instala um certificado self-signed no **Windows Root store** via `certutil -addstore Root` (só enquanto o sinkhole TLS é montado). Isso é necessário para o browser aceitar a página de foco; antivírus pode flagar esse comportamento.

Sem essa instalação, o site ainda é redirecionado via `hosts`, mas o browser mostra erro de certificado.

## Antivirus

Binários de release podem ser **unsigned**. SmartScreen/Defender podem alertar até haver reputação ou assinatura Authenticode. Submissão de falso positivo: https://www.microsoft.com/en-us/wdsi/filesubmission

## Anti-cheat

Filtros de rede + processo elevado podem conflitar com Vanguard, EasyAntiCheat, BattlEye e Faceit. Encerre a sessão e o serviço antes de abrir esses jogos. Não há allowlist pública para este tipo de app.

## Code signing (roadmap)

Assinatura Authenticode gratuita para OSS via [SignPath Foundation](https://signpath.org/) está no roadmap (após repo público + releases estáveis). Até lá, builds oficiais não prometem confiança do SmartScreen.
