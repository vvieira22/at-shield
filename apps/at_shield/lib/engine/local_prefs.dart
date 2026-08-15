import 'dart:convert';
import 'dart:io';

/// Small local prefs file next to the service DB.
///
/// ponytail: no shared_preferences — one JSON under LOCALAPPDATA/ATShield.
class LocalPrefs {
  LocalPrefs._(this._file, this._data);

  final File _file;
  final Map<String, dynamic> _data;

  static Future<LocalPrefs> open() async {
    final base = Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'] ??
        '.';
    final dir = Directory('$base${Platform.pathSeparator}ATShield');
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}ui_prefs.json');
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        final raw = jsonDecode(await file.readAsString());
        if (raw is Map<String, dynamic>) data = raw;
      } catch (_) {}
    }
    return LocalPrefs._(file, data);
  }

  String? get pin => _data['pin'] as String?;
  bool get pinEnabled => _data['pin_enabled'] == true;
  bool get startMinimized => _data['start_minimized'] == true;
  bool get launchWithWindows => _data['launch_with_windows'] == true;
  /// Minimize / close hide to the notification area instead of taskbar / quit.
  bool get minimizeToTray => _data['minimize_to_tray'] == true;
  /// X / Alt+F4 minimizes instead of quitting. Missing key = on.
  bool get closeMinimizes => _data['close_minimizes'] != false;
  /// Default focus session length (minutes).
  int get sessionDurationMins {
    final v = (_data['session_duration_mins'] as num?)?.toInt();
    if (v == null || v < 1) return 15;
    return v.clamp(1, 24 * 60);
  }

  Future<void> setPin(String? pin, {bool? enabled}) async {
    if (pin != null) _data['pin'] = pin;
    if (pin == null) _data.remove('pin');
    if (enabled != null) _data['pin_enabled'] = enabled;
    await _flush();
  }

  /// Wipe PIN + disable lock (caller must have already gated on Admin).
  Future<void> clearPin() async {
    _data.remove('pin');
    _data['pin_enabled'] = false;
    await _flush();
  }

  Future<void> setStartMinimized(bool v) async {
    _data['start_minimized'] = v;
    await _flush();
  }

  Future<void> setLaunchWithWindows(bool v) async {
    _data['launch_with_windows'] = v;
    await _flush();
  }

  Future<void> setMinimizeToTray(bool v) async {
    _data['minimize_to_tray'] = v;
    if (!v) _data['start_minimized'] = false;
    await _flush();
  }

  Future<void> setCloseMinimizes(bool v) async {
    _data['close_minimizes'] = v;
    await _flush();
  }

  Future<void> setSessionDurationMins(int mins) async {
    _data['session_duration_mins'] = mins.clamp(1, 24 * 60);
    await _flush();
  }

  String get localeCode => (_data['locale'] as String?) == 'en' ? 'en' : 'pt';

  Future<void> setLocale(String code) async {
    _data['locale'] = code == 'en' ? 'en' : 'pt';
    await _flush();
  }

  Future<void> _flush() async {
    await _file.writeAsString(const JsonEncoder.withIndent('  ').convert(_data));
  }
}
