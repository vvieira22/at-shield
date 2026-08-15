# Assert staging (or repo prerequisites) for the MSI payload.
# Runnable check: fails if packaging would ship an incomplete/broken installer.
param(
  [string]$StagingRoot = '',
  [string]$RepoRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

$failed = $false
function Fail([string]$msg) {
  Write-Host "FAIL: $msg" -ForegroundColor Red
  $script:failed = $true
}
function Ok([string]$msg) {
  Write-Host "OK: $msg"
}

# Always check repo-side installer inputs
$wxs = Join-Path $RepoRoot 'installer\AtShield.wxs'
if (Test-Path $wxs) { Ok 'installer\AtShield.wxs' } else { Fail 'missing installer\AtShield.wxs' }

$pages = @('foco.html', 'detox.html', 'style.css', 'script.js', 'lang.json', 'bonfire.png')
foreach ($p in $pages) {
  $path = Join-Path $RepoRoot "pages\$p"
  if (Test-Path $path) { Ok "pages\$p" } else { Fail "missing pages\$p" }
}

$svcMain = Join-Path $RepoRoot 'crates\at_shield_service\src\main.rs'
if (Test-Path $svcMain) {
  $txt = Get-Content -LiteralPath $svcMain -Raw
  if ($txt -match 'uninstall-cleanup') { Ok 'service --uninstall-cleanup' }
  else { Fail 'service missing --uninstall-cleanup flag' }
  if ($txt -match 'AtShieldService') { Ok 'service name AtShieldService' }
  else { Fail 'service name AtShieldService not found' }
  if ($txt -match 'crashlog::init') { Ok 'service crashlog::init' }
  else { Fail 'service missing crashlog::init' }
} else {
  Fail 'missing at_shield_service main.rs'
}

$wxsTxt = if (Test-Path $wxs) { Get-Content -LiteralPath $wxs -Raw } else { '' }
if ($wxsTxt -match 'LogsFolder') { Ok 'installer LogsFolder' }
else { Fail 'installer missing LogsFolder' }
if ($wxsTxt -match 'AtWelcomeDlg') { Ok 'installer AtWelcomeDlg' }
else { Fail 'installer missing AtWelcomeDlg' }
if ($wxsTxt -match 'AtExitDlg') { Ok 'installer AtExitDlg' }
else { Fail 'installer missing AtExitDlg' }
if ($wxsTxt -match 'UpgradeConfirmDlg') { Ok 'installer UpgradeConfirmDlg' }
else { Fail 'installer missing UpgradeConfirmDlg' }
if ($wxsTxt -match 'LaunchApplication') { Ok 'installer LaunchApplication' }
else { Fail 'installer missing LaunchApplication' }
if ($wxsTxt -match 'Abrir o A.T. Shield agora') { Ok 'installer launch-on-exit checkbox' }
else { Fail 'installer missing launch-on-exit checkbox' }

$license = Join-Path $RepoRoot 'installer\License.rtf'
if (Test-Path $license) { Ok 'installer\License.rtf' } else { Fail 'missing installer\License.rtf' }

foreach ($bmp in @('dialog.bmp', 'banner.bmp')) {
  $p = Join-Path $RepoRoot "installer\bitmaps\$bmp"
  if (Test-Path $p) { Ok "installer\bitmaps\$bmp" } else { Fail "missing installer\bitmaps\$bmp" }
}

if ($StagingRoot) {
  if (-not (Test-Path $StagingRoot)) { Fail "staging missing: $StagingRoot" }
  else {
    $need = @(
      'ui\at_shield.exe',
      'ui\flutter_windows.dll',
      'ui\data\icudtl.dat',
      'ui\data\app.so',
      'service\at-shield-service.exe',
      'pages\foco.html',
      'pages\style.css',
      'pages\script.js'
    )
    foreach ($rel in $need) {
      $p = Join-Path $StagingRoot $rel
      if (Test-Path $p) { Ok "staging\$rel" } else { Fail "staging missing $rel" }
    }
    # No source/SDK leakage
    $banned = @('Cargo.toml', 'pubspec.yaml', '.rs', 'CMakeLists.txt')
    $hits = Get-ChildItem -LiteralPath $StagingRoot -Recurse -File | Where-Object {
      $n = $_.Name
      ($n -eq 'Cargo.toml') -or ($n -eq 'pubspec.yaml') -or ($n -eq 'CMakeLists.txt') -or ($_.Extension -eq '.rs')
    }
    if ($hits) {
      Fail ("staging contains source/SDK files: " + (($hits | ForEach-Object FullName) -join ', '))
    } else {
      Ok 'staging has no Rust/Flutter sources'
    }
  }
}

if ($failed) {
  exit 1
}
Write-Host 'check-installer-layout: all good'
exit 0
