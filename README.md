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
  <img src="docs/foco.gif" alt="Página de foco do A.T. Shield" width="560" />
</p>

## Segurança

O A.T. Shield para windows é open source e roda localmente. Com uma sessão ativa, o serviço usa recursos nativos do Windows:

- filtros de saída do **WFP** para bloquear conexões;
- uma entrada identificada no arquivo `hosts`, quando a página personalizada está ativa;
- servidores locais em `127.0.0.1` e `127.0.0.2`.

Ele não faz injeção em processos, não lê memória, não captura teclas ou telas, não instala driver de kernel e não envia seus dados para a nuvem.

O Windows pode alertar sobre builds sem assinatura Authenticode, e está explicado em [SECURITY.md](SECURITY.md).

## Como usar

**Requisito:** Windows. O bloqueio de rede precisa de permissão de administrador.

1. Abra o app e o serviço.
2. Crie um perfil e adicione os sites.
3. Escolha o modo de bloqueio.
4. Defina a duração e inicie a sessão.

Sem administrador, a interface abre, mas o bloqueio de rede não é aplicado.

Antes de abrir jogos com Vanguard, EAC, BattlEye ou Faceit, encerre a sessão e feche o serviço.

## Para desenvolver

```bat 
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
