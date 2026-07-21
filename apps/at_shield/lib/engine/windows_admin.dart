import 'dart:ffi';
import 'dart:io';

import 'local_prefs.dart';

/// Windows Admin check via shell32 (no extra package).
bool isWindowsAdmin() {
  if (!Platform.isWindows) return false;
  try {
    final shell32 = DynamicLibrary.open('shell32.dll');
    final fn = shell32
        .lookupFunction<Int32 Function(), int Function()>('IsUserAnAdmin');
    return fn() != 0;
  } catch (_) {
    return false;
  }
}

String _prefsPath() {
  final base = Platform.environment['LOCALAPPDATA'] ??
      Platform.environment['APPDATA'] ??
      '.';
  return '$base${Platform.pathSeparator}ATShield'
      '${Platform.pathSeparator}ui_prefs.json';
}

/// Clear PIN. If already Admin, writes prefs directly; else UAC (RunAs).
/// Returns true when PIN lock is gone.
Future<bool> resetPinWithAdminPrompt() async {
  if (!Platform.isWindows) return false;

  if (isWindowsAdmin()) {
    final prefs = await LocalPrefs.open();
    await prefs.clearPin();
    return true;
  }

  final script = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}atshield_reset_pin.ps1',
  );
  final prefsPath = _prefsPath().replaceAll("'", "''");
  final scriptPath = script.path.replaceAll("'", "''");
  await script.writeAsString('''
\$ErrorActionPreference = 'Stop'
\$p = '$prefsPath'
\$dir = Split-Path \$p -Parent
if (-not (Test-Path \$dir)) { New-Item -ItemType Directory -Path \$dir | Out-Null }
\$data = \$null
if (Test-Path \$p) {
  try { \$data = Get-Content \$p -Raw | ConvertFrom-Json } catch { \$data = \$null }
}
\$map = [ordered]@{}
if (\$null -ne \$data) {
  foreach (\$prop in \$data.PSObject.Properties) {
    if (\$prop.Name -eq 'pin') { continue }
    if (\$prop.Name -eq 'pin_enabled') { continue }
    \$map[\$prop.Name] = \$prop.Value
  }
}
\$map['pin_enabled'] = \$false
(\$map | ConvertTo-Json -Depth 8) | Set-Content -Path \$p -Encoding UTF8
''');

  await Process.run(
    'powershell.exe',
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      "Start-Process -FilePath powershell.exe -Verb RunAs -Wait "
          "-ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass',"
          "'-File','$scriptPath')",
    ],
  );

  try {
    await script.delete();
  } catch (_) {}

  final after = await LocalPrefs.open();
  return !(after.pinEnabled && (after.pin?.isNotEmpty ?? false));
}
