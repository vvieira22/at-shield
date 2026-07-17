import 'package:flutter_test/flutter_test.dart';
import 'package:at_shield_ui/at_shield_ui.dart';

void main() {
  test('accent is red', () {
    expect(AtShieldColors.accent.toARGB32() & 0xFFFFFF, 0xE11D2E);
  });
}
