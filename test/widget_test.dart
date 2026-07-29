import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:money_manager/src/app.dart';
import 'package:money_manager/src/storage.dart';

void main() {
  testWidgets('shows the recovered sign-in screen', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MoneyManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Create account'), findsWidgets);
  });

  testWidgets('keeps the app-style bottom navigation on web', (tester) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'preview',
      'vmc-auth-password': 'preview-password',
    });
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MoneyManagerApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('keypad enters and saves a new expense', (tester) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'preview',
      'vmc-auth-password': 'preview-password',
    });
    tester.view.physicalSize = const Size(465, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MoneyManagerApp());
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Add'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.tap(find.text('000'));
    await tester.pump();
    expect(find.text('VND 1,000'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(MoneyStore.transactionsKey),
      contains('"amount":1000'),
    );
  });

  testWidgets('overview remains overflow-free at representative widths', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'preview',
      'vmc-auth-password': 'preview-password',
    });
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 1000);
      await tester.pumpWidget(const MoneyManagerApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'viewport width $width');
    }
  });
}
