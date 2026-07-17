@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

set "PATH=C:\Users\Vitor\flutter\bin;%USERPROFILE%\.cargo\bin;%PATH%"
set "ROOT=%CD%"

echo [at-shield] encerrando instancia anterior (se houver)...
taskkill /F /IM at-shield-service.exe >nul 2>&1
timeout /t 1 /nobreak >nul

echo [at-shield] compilando servico...
cargo build -p at_shield_service
if errorlevel 1 (
  echo [at-shield] cargo build falhou.
  pause
  exit /b 1
)

if not exist "%ROOT%\target\debug\at-shield-service.exe" (
  echo [at-shield] binario nao encontrado em target\debug\
  pause
  exit /b 1
)

where flutter >nul 2>&1
if errorlevel 1 (
  echo [at-shield] flutter nao encontrado no PATH.
  pause
  exit /b 1
)

echo [at-shield] subindo engine (deixe a janela preta aberta — rode como Admin)...
start "at-shield-service" /D "%ROOT%" "%ROOT%\target\debug\at-shield-service.exe" --console

echo [at-shield] aguardando IPC 127.0.0.1:47830 ...
set /a _tries=0
:wait_ipc
set /a _tries+=1
powershell -NoProfile -Command "try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1',47830); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
if not errorlevel 1 goto ipc_ok
if %_tries% GEQ 30 (
  echo [at-shield] servico nao abriu a porta a tempo.
  pause
  exit /b 1
)
timeout /t 1 /nobreak >nul
goto wait_ipc

:ipc_ok
echo [at-shield] engine online. abrindo UI Flutter...
cd /d "%ROOT%\apps\at_shield"
flutter run -d windows
if errorlevel 1 (
  echo.
  echo [at-shield] flutter run falhou.
  pause
)
