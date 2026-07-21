import 'dart:io';

/// Windows OpenFileDialog for a local `.html` / `.htm` file.
///
/// ponytail: PowerShell + WinForms instead of a file_picker dependency.
Future<String?> pickHtmlFile() async {
  if (!Platform.isWindows) return null;
  final r = await Process.run(
    'powershell',
    [
      '-NoProfile',
      '-STA',
      '-Command',
      r'''
Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.OpenFileDialog
$d.Filter = 'HTML (*.html;*.htm)|*.html;*.htm'
$d.Title = 'Escolher página de bloqueio'
if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
  Write-Output $d.FileName
}
''',
    ],
  );
  final out = (r.stdout as String).trim();
  return out.isEmpty ? null : out;
}

bool isAbsoluteHtmlPath(String p) {
  final s = p.trim();
  return RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(s) || s.startsWith(r'\\');
}

/// Preview: absolute path opens the file; relative name hits the local page server.
Future<void> openPagePreview(String page) async {
  final p = page.trim();
  if (p.isEmpty || !Platform.isWindows) return;
  final target = isAbsoluteHtmlPath(p)
      ? p
      : 'http://127.0.0.1:47831/${p.replaceAll('\\', '/').split('/').last}';
  await Process.run('cmd', ['/c', 'start', '', target]);
}
