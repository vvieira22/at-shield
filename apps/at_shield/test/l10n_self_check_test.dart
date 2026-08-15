import 'package:at_shield/l10n/app_strings.dart';
import 'package:at_shield/l10n/locale_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppStrings pt/en key pairs', () {
    expect(AppStrings.en.settings, 'Settings');
    expect(AppStrings.pt.settings, 'Configurações');
    expect(AppStrings.en.cancel, isNot(AppStrings.pt.cancel));
    expect(AppStrings.en.startSession, isNot(AppStrings.pt.startSession));
    expect(AppStrings.en.copySuffix, ' (copy)');
    expect(AppStrings.pt.copySuffix, ' (cópia)');
    expect(AppStrings.pt.closeMinimizes, 'Fechar minimiza a aplicação');
    expect(AppStrings.en.closeMinimizes, 'Close minimizes the app');
    expect(AppStrings.en.quitAppConfirm, 'Quit');
  });

  test('LocaleController toggles pt/en', () async {
    final lc = LocaleController.instance;
    final before = lc.lang;
    lc.lang = AppLang.en;
    expect(lc.strings, AppStrings.en);
    lc.lang = AppLang.pt;
    expect(lc.strings, AppStrings.pt);
    lc.lang = before;
  });
}
