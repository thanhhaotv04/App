import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/src/app.dart';
import 'package:money_manager/src/storage.dart';
import 'package:money_manager/src/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets('overview stays visually stable', (tester) async {
    await _pumpPreview(tester);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/overview.png'),
    );
  });

  testWidgets('add stays visually stable', (tester) async {
    await _pumpPreview(tester);
    await _openTab(tester, 'Add');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/add.png'),
    );
  });

  testWidgets('history stays visually stable', (tester) async {
    await _pumpPreview(tester);
    await _openTab(tester, 'History');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/history.png'),
    );
  });

  testWidgets('account stays visually stable', (tester) async {
    await _pumpPreview(tester);
    await _openTab(tester, 'Account');
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/account.png'),
    );
  });
}

Future<void> _pumpPreview(WidgetTester tester) async {
  final previewNow = DateTime(2026, 8, 22, 10);
  SharedPreferences.setMockInitialValues({
    'vmc-auth-user': 'thanhhao',
    'vmc-auth-password': 'preview-password',
    MoneyStore.transactionsKey: jsonEncode([
      {
        'id': 'preview-income',
        'title': 'Salary',
        'note': 'August',
        'category': 'Income',
        'amount': 18000000,
        'date': '2026-08-01T09:00:00.000',
        'type': 'income',
        'icon': 58730,
      },
      {
        'id': 'preview-food',
        'title': 'Lunch',
        'note': 'Office meal',
        'category': 'Food',
        'amount': 65000,
        'date': '2026-08-22T07:00:00.000',
        'type': 'expense',
        'icon': 59474,
      },
      {
        'id': 'preview-shopping',
        'title': 'Groceries',
        'note': 'Household items',
        'category': 'Shopping',
        'amount': 385000,
        'date': '2026-08-20T18:00:00.000',
        'type': 'expense',
        'icon': 58918,
      },
      {
        'id': 'preview-fun',
        'title': 'Movie',
        'note': 'Weekend',
        'category': 'Fun',
        'amount': 90000,
        'date': '2026-07-24T20:00:00.000',
        'type': 'expense',
        'icon': 57940,
      },
    ]),
  });
  await AuthCache.save(
    const AuthSession(
      name: 'thanhhao',
      id: 'preview-id',
      token: 'preview-token',
      backendUrl: 'https://192.168.1.141:3002',
    ),
  );
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

  await tester.pumpWidget(
    MoneyManagerApp(
      now: previewNow,
      previewVersionName: '1.0.8',
      previewVersionCode: 9,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  final destination = find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );
  await tester.tap(destination);
  await tester.pumpAndSettle();
}
