import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../engine/local_prefs.dart';
import 'app_strings.dart';

enum AppLang { pt, en }

class LocaleController extends ChangeNotifier {
  LocaleController._();

  static final instance = LocaleController._();

  AppLang lang = AppLang.pt;

  AppStrings get strings => lang == AppLang.en ? AppStrings.en : AppStrings.pt;

  Future<void> load() async {
    final prefs = await LocalPrefs.open();
    final code = prefs.localeCode;
    lang = code == 'en' ? AppLang.en : AppLang.pt;
    await _writeLangJson(code);
    notifyListeners();
  }

  Future<void> setLang(AppLang l) async {
    lang = l;
    final code = l == AppLang.en ? 'en' : 'pt';
    final prefs = await LocalPrefs.open();
    await prefs.setLocale(code);
    await _writeLangJson(code);
    notifyListeners();
  }

  Future<void> _writeLangJson(String code) async {
    final content = const JsonEncoder().convert({'lang': code});
    for (final dir in _candidateDirs()) {
      try {
        if (!await dir.exists()) await dir.create(recursive: true);
        final file = File('${dir.path}${Platform.pathSeparator}lang.json');
        await file.writeAsString(content);
      } catch (_) {}
    }
  }

  List<Directory> _candidateDirs() {
    final out = <Directory>[];
    out.add(Directory('pages'));
    try {
      final exe = Platform.resolvedExecutable;
      out.add(Directory(
        '${File(exe).parent.path}${Platform.pathSeparator}pages',
      ));
    } catch (_) {}
    out.add(Directory('..${Platform.pathSeparator}..${Platform.pathSeparator}pages'));
    return out;
  }
}

AppStrings get s => LocaleController.instance.strings;
