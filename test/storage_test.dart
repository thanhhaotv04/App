import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/src/models.dart';
import 'package:money_manager/src/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const alice = AuthSession(
  name: 'alice',
  backendUrl: 'https://server.example',
  id: 'alice-id',
  token: 'test-token',
);
const bob = AuthSession(
  name: 'bob',
  backendUrl: 'https://server.example',
  id: 'bob-id',
  token: 'test-token',
);
Tx transaction(String id) => Tx(
  id: id,
  title: 'Private lunch',
  category: 'Food',
  amount: 30000,
  date: DateTime.utc(2026, 9, 19),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test('server configuration validates transport and address', () async {
    expect(await BackendConfig.loadUrl(), startsWith('https://'));
    for (final url in [
      'http://192.168.1.2:3002',
      'https://name:password@host',
      'file:///etc/passwd',
      'https://host?token=secret',
      'https://host/path',
    ]) {
      await expectLater(BackendConfig.saveUrl(url), throwsFormatException);
    }
    await BackendConfig.saveUrl(' https://server.example:3002/ ');
    expect(await BackendConfig.loadUrl(), 'https://server.example:3002');
  });

  test('local account verifies password and restores encrypted data', () async {
    final first = await AuthCache.registerOffline('thanhhao', 'local-password');
    expect(first.isOffline, isTrue);
    expect(first.name, 'thanhhao');
    final store = await MoneyStore.load();
    await store.addExpense(transaction('offline-private'));

    await AuthCache.signOutLocally(first);
    await expectLater(
      AuthCache.signInOffline('thanhhao', 'wrong-password'),
      throwsFormatException,
    );
    final otherUser = await AuthCache.registerOffline(
      'bob',
      'bob-long-password',
    );
    expect(otherUser.id, first.id);
    expect((await MoneyStore.load()).transactions(), isEmpty);

    await AuthCache.signOutLocally(otherUser);
    final reopened = await AuthCache.signInOffline(
      'THANHHAO',
      'local-password',
    );

    expect(reopened.id, first.id);
    expect(reopened.name, 'thanhhao');
    expect(
      (await MoneyStore.load()).transactions().single.id,
      'offline-private',
    );
    await expectLater(
      AuthCache.registerOffline('thanhhao', 'another-password'),
      throwsFormatException,
    );
  });

  test('local account rejects invalid credentials', () async {
    await expectLater(
      AuthCache.registerOffline('   ', 'password'),
      throwsFormatException,
    );
    await expectLater(
      AuthCache.registerOffline('bad\u0000name', 'password'),
      throwsFormatException,
    );
    await expectLater(
      AuthCache.registerOffline('a' * 81, 'password'),
      throwsFormatException,
    );
    await expectLater(
      AuthCache.registerOffline('alice', '123'),
      throwsFormatException,
    );
    await expectLater(
      AuthCache.signInOffline('missing', 'password'),
      throwsFormatException,
    );
  });

  test(
    'data is encrypted and isolated across accounts, servers and relaunch',
    () async {
      await AuthCache.save(alice);
      final store = await MoneyStore.load();
      await store.addExpense(transaction('alice-private'));
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(store.storageKey),
        isNot(contains('Private lunch')),
      );
      expect(prefs.getString(MoneyStore.transactionsKey), isNull);
      await AuthCache.clear();
      await AuthCache.save(bob);
      expect((await MoneyStore.load()).transactions(), isEmpty);
      final elsewhere = AuthSession(
        name: alice.name,
        id: alice.id,
        backendUrl: 'https://elsewhere.example',
        token: alice.token,
      );
      expect(
        (await MoneyStore.load(session: elsewhere)).transactions(),
        isEmpty,
      );
      await AuthCache.save(alice);
      expect(
        (await MoneyStore.load()).transactions().single.id,
        'alice-private',
      );
    },
  );

  test(
    'legacy credentials do not assign shared data to the last signed-in user',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthCache.userKey: 'alice',
        AuthCache.passwordKey: 'legacy-password',
        BackendConfig.key: 'http://server.example:3002',
        MoneyStore.transactionsKey: jsonEncode([
          transaction('legacy').toJson(),
        ]),
      });
      final old = await AuthCache.load();
      expect(old!.id, isEmpty);
      expect(
        await AuthCache.secure.read(key: AuthCache.sessionKey),
        isNot(contains('legacy-password')),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AuthCache.passwordKey), isNull);
      final upgraded = AuthSession(
        name: 'alice',
        id: 'alice-id',
        backendUrl: 'https://server.example:3002',
        token: 'new-token',
      );
      await AuthCache.save(upgraded);
      final store = await MoneyStore.load();
      expect(store.transactions(), isEmpty);
      expect(await store.hasRecoveryData(), isTrue);
      await expectLater(
        store.readRecoveryData(confirmed: false),
        throwsFormatException,
      );
      final recovery = await store.readRecoveryData(confirmed: true);
      expect(recovery.transactions.single.id, 'legacy');
      await store.replaceAll(recovery);
      expect(store.transactions().single.id, 'legacy');
      expect(prefs.getString(MoneyStore.transactionsKey), isNotNull);
      expect((await AuthCache.load())!.token, 'new-token');
      await AuthCache.clear();
      await AuthCache.save(bob);
      expect((await MoneyStore.load()).transactions(), isEmpty);
    },
  );

  test(
    'unowned legacy data is preserved and is never silently assigned',
    () async {
      final legacy = jsonEncode([transaction('unowned').toJson()]);
      SharedPreferences.setMockInitialValues({
        MoneyStore.transactionsKey: legacy,
      });
      await AuthCache.save(bob);
      expect((await MoneyStore.load()).transactions(), isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString(
          MoneyStore.transactionsKey,
        ),
        legacy,
      );
    },
  );

  test(
    'corrupt encrypted data is preserved instead of silently reset',
    () async {
      final store = await MoneyStore.load(session: alice);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(store.storageKey, 'corrupt');
      await expectLater(MoneyStore.load(session: alice), throwsFormatException);
      expect(prefs.getString(store.storageKey), 'corrupt');
    },
  );

  test(
    'deletions survive stale sync and Undo restores one new record',
    () async {
      final store = await MoneyStore.load(session: alice);
      final tx = transaction('delete-me');
      await store.addExpense(tx);
      await store.removeTransaction(tx.id);
      await store.replaceAll(MoneySyncData([tx], []));
      expect(store.transactions(), isEmpty);
      expect(store.snapshot.deletedTransactions, contains(tx.id));
      await store.restoreTransaction(tx);
      expect(store.transactions().single.id, isNot(tx.id));
      expect(store.transactions().single.amount, tx.amount);
    },
  );

  test('parallel local writes and edits during sync are retained', () async {
    final store = await MoneyStore.load(session: alice);
    await Future.wait(
      List.generate(10, (i) => store.addExpense(transaction('local-$i'))),
    );
    await store.replaceAll(MoneySyncData([transaction('remote')], []));
    expect(store.transactions(), hasLength(11));
    expect(
      (await MoneyStore.load(session: alice)).transactions(),
      hasLength(11),
    );
  });

  test('recurring expenses do not regenerate a deleted occurrence', () async {
    final store = await MoneyStore.load(session: alice);
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    await store.addRecurring(
      RecurringExpense(
        id: 'rule',
        title: 'Lunch',
        amount: 10000,
        category: 'Food',
        frequency: RecurringFrequency.daily,
        lastAppliedAt: yesterday,
      ),
    );
    await store.applyDueRecurringExpenses();
    final occurrence = store.transactions().single;
    await store.removeTransaction(occurrence.id);
    await store.applyDueRecurringExpenses();
    expect(store.transactions(), isEmpty);
  });
}
