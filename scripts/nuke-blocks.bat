@echo off
:: Kill service + wipe orphan WFP filters that keep blocking sites after disable.
:: MUST run as Administrator (right-click → Run as administrator).
setlocal
cd /d "%~dp0.."
set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"

echo [at-shield] matando servico...
taskkill /F /IM at-shield-service.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo [at-shield] compilando nuke...
cargo build -p at_shield_service --target-dir target_new
if errorlevel 1 (
  echo build falhou
  pause
  exit /b 1
)

echo [at-shield] executando --nuke ...
"target_new\debug\at-shield-service.exe" --nuke
set ERR=%ERRORLEVEL%

echo [at-shield] flush dns...
ipconfig /flushdns >nul

echo.
if %ERR%==0 (
  echo OK. Fecha o Chrome POR COMPLETO e testa twitter.com / instagram.com
) else (
  echo FALHOU — esta janela PRECISA ser "Executar como administrador"
)
pause
