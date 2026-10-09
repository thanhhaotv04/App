import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:money_manager/src/app.dart';
import 'package:money_manager/src/storage.dart';
import 'package:money_manager/src/models.dart';

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      AuthCache.sessionKey: jsonEncode(
        const AuthSession(
          name: 'preview',
          id: 'preview-id',
          token: 'preview-token',
          backendUrl: BackendConfig.defaultUrl,
        ).toJson(),
      ),
    }),
  );
  testWidgets('sign-in keeps password and hides backend URL', (tester) async {
    String? submittedUser;
    String? submittedPassword;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (user, password) async {
            submittedUser = user;
            submittedPassword = password;
            return null;
          },
          onRegister: (_, _) async => null,
        ),
      ),
    );

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Backend URL'), findsNothing);
    expect(find.text('Reset password'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(
      tester.widgetList<TextField>(find.byType(TextField)).last.obscureText,
      isTrue,
    );

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(
      tester.widgetList<TextField>(find.byType(TextField)).last.obscureText,
      isFalse,
    );

    await tester.enterText(find.byType(TextField).first, 'thanhhao');
    await tester.enterText(find.byType(TextField).last, 'correct-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(submittedUser, 'thanhhao');
    expect(submittedPassword, 'correct-password');
  });

  testWidgets('registration requires matching password confirmation', (
    tester,
  ) async {
    String? submittedUser;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, _) async => null,
          onRegister: (user, _) async {
            submittedUser = user;
            return null;
          },
        ),
      ),
    );

    await tester.tap(find.text('Register'));
    await tester.pump();

    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(3));

    await tester.enterText(find.byType(TextField).at(0), 'thanhhao');
    await tester.enterText(find.byType(TextField).at(1), 'local-password');
    await tester.enterText(find.byType(TextField).at(2), 'different-password');
    final createButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pump();

    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(submittedUser, isNull);

    await tester.enterText(find.byType(TextField).at(2), 'local-password');
    await tester.tap(createButton);
    await tester.pump();

    expect(submittedUser, 'thanhhao');
  });

  testWidgets('creates a local account without a backend', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MoneyManagerApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), 'thanhhao');
    await tester.enterText(find.byType(TextField).at(1), 'local-password');
    await tester.enterText(find.byType(TextField).at(2), 'local-password');
    final createButton = find.widgetWithText(FilledButton, 'Create account');
    await tester.ensureVisible(createButton);
    await tester.tap(createButton);
    await tester.pumpAndSettle();

    expect(find.text('Overview'), findsWidgets);
    final session = await AuthCache.load();
    expect(session?.isOffline, isTrue);
    expect(session?.name, 'thanhhao');
  });

  testWidgets('falls back to local sign-in when the saved session is corrupt', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      AuthCache.sessionKey: 'not valid json',
    });
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const MoneyManagerApp());
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.textContaining('Could not unlock'), findsNothing);
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
    final store = await MoneyStore.load();
    expect(store.transactions().single.amount, 1000);
    expect(store.transactions().single.type, TxType.expense);
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

    final store = await MoneyStore.load();
    expect(store.transactions().single.type, TxType.income);
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
    final prefs = await SharedPreferences.getInstance();
    final store = await MoneyStore.load();
    await store.saveTransactions(
      (jsonDecode(prefs.getString(MoneyStore.transactionsKey)!) as List)
          .map((v) => Tx.fromJson(Map<String, Object?>.from(v as Map)))
          .toList(),
    );
    await prefs.remove(MoneyStore.transactionsKey);
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
    final restored = await MoneyStore.load();
    expect(restored.transactions(), hasLength(1));
    expect(restored.transactions().single.title, 'Coffee');
    expect(restored.transactions().single.id, isNot('delete-preview'));
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
