import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:task_reminder/src/app.dart';
import 'package:task_reminder/src/storage.dart';

void main() {
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      const fontPath = String.fromEnvironment('PREVIEW_FONT');
      final bytes = ByteData.sublistView(await File(fontPath).readAsBytes());
      await (FontLoader('Roboto')..addFont(Future.value(bytes))).load();
      await (FontLoader('Ahem')..addFont(Future.value(bytes))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });
  setUp(() {
    TaskReminderApp.themeMode.value = ThemeMode.light;
    FlutterSecureStorage.setMockInitialValues({});
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
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/review/account.png'),
      );
    }
  });

  testWidgets('offline account screen renders at mobile preview size', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const TaskReminderApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('No server is required.'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.textContaining('Backend URL'), findsNothing);
    if (const bool.fromEnvironment('CAPTURE_PREVIEW')) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../build/review/auth.png'),
      );
    }
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
