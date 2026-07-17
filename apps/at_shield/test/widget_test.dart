import 'package:flutter_test/flutter_test.dart';
import 'package:at_shield/main.dart';

void main() {
  testWidgets('A.T. Shield boots shell', (tester) async {
    await tester.pumpWidget(const AtShieldApp());
    await tester.pump();
    expect(find.textContaining('A.T. SHIELD'), findsWidgets);
  });
}
