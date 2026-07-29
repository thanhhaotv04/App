import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('mobile reference views stay visually stable', (tester) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'thanhhao',
      'vmc-auth-password': 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MoneyManagerApp());
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/overview.png'),
    );

    await _openTab(tester, 'Add');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/add.png'),
    );

    await _openTab(tester, 'History');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/history.png'),
    );

    await _openTab(tester, 'Account');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/account.png'),
    );
  });
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final destination = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  await tester.tap(destination);
  await tester.pumpAndSettle();
}
