@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

echo [at-shield] limpando WFP + hosts (precisa Admin)...
set "EXE="
if exist "%CD%\target\debug\at-shield-service.exe" set "EXE=%CD%\target\debug\at-shield-service.exe"
if exist "%CD%\target\release\at-shield-service.exe" set "EXE=%CD%\target\release\at-shield-service.exe"
if "%EXE%"=="" (
  echo [at-shield] compilando servico...
  cargo build -p at_shield_service
  set "EXE=%CD%\target\debug\at-shield-service.exe"
)

powershell -NoProfile -Command "Start-Process -FilePath '%EXE%' -ArgumentList '--nuke' -Verb RunAs -Wait"
ipconfig /flushdns >nul
echo [at-shield] pronto — testa o site de novo.
pause
