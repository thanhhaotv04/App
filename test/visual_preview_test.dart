import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:task_reminder/src/app.dart';
import 'package:task_reminder/src/storage.dart';

void main() {
  setUp(() {
    TaskReminderApp.themeMode.value = ThemeMode.light;
  });

  testWidgets('main task views render at mobile preview size', (tester) async {
    SharedPreferences.setMockInitialValues({
      AuthCache.userKey: 'thanhhao',
      AuthCache.passwordKey: 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsWidgets);

    await _openTab(tester, 'Daily');
    expect(find.text('Daily'), findsWidgets);

    await _openTab(tester, 'Work list');
    expect(find.text('Work list'), findsWidgets);

    await _openTab(tester, 'Account');
    expect(find.text('Account'), findsWidgets);
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
