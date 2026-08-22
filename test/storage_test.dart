import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/src/models.dart';
import 'package:money_manager/src/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses the configured LAN sync endpoint by default', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await BackendConfig.loadUrl(), 'http://192.168.1.141:3002');
  });

  test(
    'migrates the recovered localhost endpoint to the LAN endpoint',
    () async {
      SharedPreferences.setMockInitialValues({
        BackendConfig.key: BackendConfig.legacyDefaultUrl,
      });

      expect(await BackendConfig.loadUrl(), BackendConfig.defaultUrl);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BackendConfig.key), BackendConfig.defaultUrl);
    },
  );

  test('starts empty and persists only transactions the user enters', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await MoneyStore.load();

    expect(store.transactions(), isEmpty);

    await store.addExpense(
      Tx(
        id: 'new-entry',
        title: 'Coffee',
        category: 'Food',
        amount: 30000,
        date: DateTime.utc(2026, 8, 22, 9),
      ),
    );

    final prefs = await SharedPreferences.getInstance();
    final stored =
        jsonDecode(prefs.getString(MoneyStore.transactionsKey)!)
            as List<dynamic>;
    expect(stored, hasLength(1));
    expect((stored.single as Map<String, dynamic>)['id'], 'new-entry');
  });
}
