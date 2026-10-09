// Test-only entry point: flutter build web --target tool/browser_storage_probe.dart
// Serve the output on localhost; drive it with check_browser_storage.mjs.
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/widgets.dart';
import 'package:money_manager/src/models.dart';
import 'package:money_manager/src/storage.dart';

@JS('moneyManagerProbe')
external set _probe(JSFunction value);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MoneyStore? store;
  _probe = ((JSString input) {
    return (() async {
      final command = jsonDecode(input.toDart) as Map<String, dynamic>;
      switch (command['op']) {
        case 'login':
          await AuthCache.save(
            AuthSession.fromJson(command['session'] as Map<String, dynamic>),
          );
        case 'open':
          store = await MoneyStore.load();
        case 'add':
          await store!.addExpense(
            Tx(
              id: command['id'] as String,
              title: 'Browser probe',
              category: 'Food',
              amount: 10000,
              date: DateTime(2026, 9, 19),
            ),
          );
        case 'remove':
          await store!.removeTransaction(command['id'] as String);
        case 'bulk':
          await store!.replaceAll(
            MoneySyncData(
              List.generate(
                2400,
                (i) => Tx(
                  id: 'large-$i',
                  title: 't' * 500,
                  note: 'n' * 2000,
                  category: 'Food',
                  amount: 10000,
                  date: DateTime(2026, 9, 19),
                ),
              ),
              [],
            ),
          );
        case 'read':
          await store!.refresh();
          return jsonEncode(
            store!.transactions().map((tx) => tx.id).toList(),
          ).toJS;
        case 'guard':
          try {
            await AuthCache.requireCurrent(store!.session);
            return 'allowed'.toJS;
          } on FormatException {
            return 'blocked'.toJS;
          }
      }
      return 'ok'.toJS;
    })().toJS;
  }).toJS;
  runApp(const SizedBox.shrink());
}
