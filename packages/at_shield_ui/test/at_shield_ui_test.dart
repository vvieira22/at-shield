import 'package:flutter_test/flutter_test.dart';
import 'package:at_shield_ui/at_shield_ui.dart';

void main() {
  test('accent matches brand red', () {
    expect(AtShieldColors.accent.toARGB32() & 0xFFFFFF, 0xE51E25);
  });

  test('bg is near-black charcoal', () {
    expect(AtShieldColors.bg.toARGB32() & 0xFFFFFF, 0x0D0D0D);
  });
}
