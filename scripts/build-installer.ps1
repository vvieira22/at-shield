# Build Release binaries + MSI installer for A.T. Shield.
# Requires (build machine only): Flutter, Rust, Visual Studio C++ tools, WiX CLI (`winget install WiXToolset.WiXCLI`).
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\build-installer.ps1
# Optional:
#   -SkipFlutter / -SkipRust   reuse existing Release outputs
#   -SignThumbprint <hex>      Authenticode via signtool (cert in CurrentUser\My or LocalMachine\My)
#   -Version 1.0.0
param(
  [string]$Version = '1.0.0',
  [switch]$SkipFlutter,
  [switch]$SkipRust,
  [string]$SignThumbprint = $env:ATSHIELD_SIGN_THUMBPRINT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Staging = Join-Path $Root 'installer\staging'
$Gen = Join-Path $Root 'installer\generated'
$Dist = Join-Path $Root 'dist'
$MsiName = "ATShield-$Version.msi"
$MsiPath = Join-Path $Dist $MsiName

function Find-Tool([string]$Name, [string[]]$ExtraPaths = @()) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($p in $ExtraPaths) {
    $candidate = Join-Path $p $Name
    if (Test-Path $candidate) { return $candidate }
  }
  return $null
}

function Assert-File([string]$Path, [string]$Label) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Missing $Label`: $Path"
  }
}

Write-Host "[at-shield] root=$Root"

# --- tools ---
$flutter = Find-Tool 'flutter.bat' @(
  'C:\Users\Vitor\flutter\bin',
  (Join-Path $env:USERPROFILE 'flutter\bin'),
  'C:\flutter\bin'
)
if (-not $flutter) { $flutter = Find-Tool 'flutter' @() }
$cargo = Find-Tool 'cargo.exe' @((Join-Path $env:USERPROFILE '.cargo\bin'))
$wix = Find-Tool 'wix.exe' @()

if (-not $cargo) { throw 'cargo not found — install Rust (https://rustup.rs)' }
if (-not $wix) {
  throw 'wix not found — install with: winget install --id WiXToolset.WiXCLI -e'
}
if (-not $SkipFlutter -and -not $flutter) {
  throw 'flutter not found — install Flutter or pass -SkipFlutter if Release UI already built'
}

Write-Host "[at-shield] cargo=$cargo"
Write-Host "[at-shield] wix=$(& $wix --version)"
if ($flutter) { Write-Host "[at-shield] flutter=$flutter" }

# --- build ---
# Keep artifacts in-repo (some agents/sandboxes redirect cargo target elsewhere).
$env:CARGO_TARGET_DIR = Join-Path $Root 'target'

if (-not $SkipRust) {
  Write-Host '[at-shield] cargo build -p at_shield_service --release'
  Push-Location $Root
  try {
    & $cargo build -p at_shield_service --release
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed ($LASTEXITCODE)" }
  } finally { Pop-Location }
}

$serviceExe = Join-Path $Root 'target\release\at-shield-service.exe'
Assert-File $serviceExe 'service Release binary'

if (-not $SkipFlutter) {
  Write-Host '[at-shield] flutter build windows --release'
  $appDir = Join-Path $Root 'apps\at_shield'
  Push-Location $appDir
  try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed ($LASTEXITCODE)" }
    & $flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed ($LASTEXITCODE)" }
  } finally { Pop-Location }
}

$uiRelease = Join-Path $Root 'apps\at_shield\build\windows\x64\runner\Release'
if (-not (Test-Path $uiRelease)) {
  $uiRelease = Join-Path $Root 'apps\at_shield\build\windows\runner\Release'
}
Assert-File (Join-Path $uiRelease 'at_shield.exe') 'Flutter Release UI'

# --- stage ---
Write-Host '[at-shield] staging payload (no SDKs / no sources)'
if (Test-Path $Staging) { Remove-Item -LiteralPath $Staging -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $Staging 'ui') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Staging 'service') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Staging 'pages') | Out-Null
if (Test-Path $Gen) { Remove-Item -LiteralPath $Gen -Recurse -Force }
New-Item -ItemType Directory -Path $Gen | Out-Null
if (-not (Test-Path $Dist)) { New-Item -ItemType Directory -Path $Dist | Out-Null }

Copy-Item -Path (Join-Path $uiRelease '*') -Destination (Join-Path $Staging 'ui') -Recurse -Force
Copy-Item -Path $serviceExe -Destination (Join-Path $Staging 'service\at-shield-service.exe') -Force
Copy-Item -Path (Join-Path $Root 'pages\*') -Destination (Join-Path $Staging 'pages') -Recurse -Force

# Layout self-check (fails the build if packaging is incomplete)
& (Join-Path $PSScriptRoot 'check-installer-layout.ps1') -StagingRoot $Staging
if ($LASTEXITCODE -ne 0) { throw 'installer layout check failed' }

# Optional Authenticode on staged exes before harvest
function Invoke-Sign([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($SignThumbprint)) { return }
  $signtool = Find-Tool 'signtool.exe' @(
    "${env:ProgramFiles(x86)}\Windows Kits\10\bin\x64",
    "${env:ProgramFiles(x86)}\Windows Kits\10\App Certification Kit"
  )
  if (-not $signtool) {
    $kits = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending
    foreach ($k in $kits) {
      $c = Join-Path $k.FullName 'x64\signtool.exe'
      if (Test-Path $c) { $signtool = $c; break }
    }
  }
  if (-not $signtool) { throw 'signtool.exe not found (Windows SDK)' }
  Write-Host "[at-shield] signing $Path"
  & $signtool sign /sha1 $SignThumbprint /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 $Path
  if ($LASTEXITCODE -ne 0) { throw "signtool failed for $Path ($LASTEXITCODE)" }
}

Invoke-Sign (Join-Path $Staging 'ui\at_shield.exe')
Invoke-Sign (Join-Path $Staging 'service\at-shield-service.exe')

# --- harvest ---
$harvest = Join-Path $PSScriptRoot 'New-WixFileHarvest.ps1'
& $harvest -StagingRoot $Staging -RelativeDir 'ui' -DirectoryId 'INSTALLFOLDER' `
  -ComponentGroupId 'UiFiles' -OutFile (Join-Path $Gen 'UiFiles.wxs') `
  -ExcludeNames @('at_shield.exe')
& $harvest -StagingRoot $Staging -RelativeDir 'pages' -DirectoryId 'PagesFolder' `
  -ComponentGroupId 'PagesFiles' -OutFile (Join-Path $Gen 'PagesFiles.wxs')

# --- wix build ---
Write-Host "[at-shield] wix build → $MsiPath"
$wixArgs = @(
  'build',
  (Join-Path $Root 'installer\AtShield.wxs'),
  (Join-Path $Gen 'UiFiles.wxs'),
  (Join-Path $Gen 'PagesFiles.wxs'),
  '-d', "ProductVersion=$Version",
  '-d', "ProjectRoot=$Root",
  '-b', "Staging=$Staging",
  '-arch', 'x64',
  '-acceptEula', 'wix7',
  '-o', $MsiPath
)
& $wix @wixArgs
if ($LASTEXITCODE -ne 0) { throw "wix build failed ($LASTEXITCODE)" }

Invoke-Sign $MsiPath

$unsignedNote = if ([string]::IsNullOrWhiteSpace($SignThumbprint)) {
  'UNSIGNED (beta) — set ATSHIELD_SIGN_THUMBPRINT or -SignThumbprint for Authenticode'
} else {
  'signed'
}

Write-Host ""
Write-Host "[at-shield] MSI ready: $MsiPath ($unsignedNote)"
Write-Host "[at-shield] Install elevates once (UAC). Service=LocalSystem, UI=user."
