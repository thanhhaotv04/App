import 'dart:convert';

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

  testWidgets('new accounts start with a clear empty state', (tester) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'preview',
      'vmc-auth-password': 'preview-password',
    });

    await tester.pumpWidget(const MoneyManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('No transactions yet.'), findsOneWidget);
    expect(find.text('Add a transaction'), findsOneWidget);
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

    final saveExpense = find.widgetWithText(FilledButton, 'Save expense');
    await tester.ensureVisible(saveExpense);
    await tester.tap(saveExpense);
    await tester.pumpAndSettle();
    expect(find.text('Overview'), findsWidgets);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(MoneyStore.transactionsKey),
      contains('"amount":1000'),
    );
    expect(
      prefs.getString(MoneyStore.transactionsKey),
      contains('"type":"expense"'),
    );
  });

  testWidgets('income selector saves an income transaction', (tester) async {
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

    await tester.tap(find.text('Income'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('2'));
    await tester.tap(find.text('000'));
    await tester.pump();
    expect(find.text('VND 2,000'), findsOneWidget);
    final saveIncome = find.widgetWithText(FilledButton, 'Save income');
    await tester.ensureVisible(saveIncome);
    await tester.tap(saveIncome);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(MoneyStore.transactionsKey),
      contains('"type":"income"'),
    );
  });

  testWidgets('quick entry remains overflow-free on a narrow phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'preview',
      'vmc-auth-password': 'preview-password',
    });
    tester.view.physicalSize = const Size(375, 900);
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

    expect(tester.takeException(), isNull);
  });

  testWidgets('history confirms deletion and offers undo', (tester) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'preview',
      'vmc-auth-password': 'preview-password',
      MoneyStore.transactionsKey: jsonEncode([
        {
          'id': 'delete-preview',
          'title': 'Coffee',
          'note': '',
          'category': 'Food',
          'amount': 30000,
          'date': '2026-08-22T09:00:00.000',
          'type': 'expense',
          'icon': 59474,
        },
      ]),
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
        matching: find.text('History'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete transaction'));
    await tester.pumpAndSettle();
    expect(find.text('Delete transaction?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(MoneyStore.transactionsKey),
      contains('delete-preview'),
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
