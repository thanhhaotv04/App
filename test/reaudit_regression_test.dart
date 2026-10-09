import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money_manager/src/app.dart';
import 'package:money_manager/src/storage.dart';
import 'package:money_manager/src/services.dart';
import 'package:money_manager/src/models.dart';

const alice = AuthSession(
  name: 'alice',
  id: 'alice-id',
  token: 'alice-token',
  backendUrl: 'https://server.example:3002',
);
const bob = AuthSession(
  name: 'bob',
  id: 'bob-id',
  token: 'bob-token',
  backendUrl: 'https://server.example:3002',
);
Tx tx(String id) => Tx(
  id: id,
  title: 'Private expense',
  category: 'Food',
  amount: 10000,
  date: DateTime(2026, 9, 19),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      BackendConfig.key: alice.backendUrl,
    });
  });
  testWidgets(
    'stale Alice page cannot send data with the current Bob session',
    (tester) async {
      await AuthCache.save(alice);
      final store = await MoneyStore.load(session: alice);
      await store.addExpense(tx('alice-private'));
      var requests = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: AccountPage(
                  store: store,
                  transactions: store.transactions(),
                  recurring: [],
                  session: alice,
                  onReload: () async {},
                  onLogout: () {},
                  onChangePassword: (_, _, _) async => null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await AuthCache.save(bob);
          final button = find.widgetWithText(OutlinedButton, 'Sync now');
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );
      expect(requests, 0);
      expect(find.textContaining('account changed'), findsOneWidget);
      expect((await AuthCache.load())!.id, bob.id);
    },
  );
  test(
    'two stores preserve concurrent writes, deletes and subsequent refresh',
    () async {
      final stores = await Future.wait([
        MoneyStore.load(session: alice),
        MoneyStore.load(session: alice),
      ]);
      await Future.wait(
        List.generate(12, (i) => stores[i % 2].addExpense(tx('window-$i'))),
      );
      await stores.first.removeTransaction('window-0');
      await stores.last.addExpense(tx('after-delete'));
      await stores.first.refresh();
      expect(stores.first.transactions(), hasLength(12));
      expect(
        stores.first.transactions().map((t) => t.id),
        isNot(contains('window-0')),
      );
      expect(
        (await MoneyStore.load(session: alice)).transactions(),
        hasLength(12),
      );
    },
  );
  test(
    'reused username with a new account ID never inherits prior data',
    () async {
      final first = await MoneyStore.load(session: alice);
      await first.addExpense(tx('old-account-private'));
      final replacement = AuthSession(
        name: alice.name,
        backendUrl: alice.backendUrl,
        id: 'different-account-id',
        token: 'different-token',
      );
      expect(
        (await MoneyStore.load(session: replacement)).transactions(),
        isEmpty,
      );
      expect(
        (await MoneyStore.load(session: alice)).transactions().single.id,
        'old-account-private',
      );
    },
  );
  test(
    'installer failure retains actionable permission and signing messages',
    () {
      for (final reason in [
        'Allow updates from Money Manager, then check for updates again.',
        'The update signing key does not match this app. Contact the server owner.',
      ]) {
        expect(
          friendlyError(
            PlatformException(code: 'install_failed', message: reason),
          ),
          reason,
        );
      }
    },
  );
  test(
    'newer remote transaction wins, equal timestamp uses server copy',
    () async {
      final store = await MoneyStore.load(session: alice);
      await store.addExpense(tx('same-id'));
      final newer = Tx(
        id: 'same-id',
        title: 'Remote corrected',
        category: 'Food',
        amount: 20000,
        date: DateTime(2026, 9, 20),
      );
      await store.replaceAll(MoneySyncData([newer], []));
      expect(store.transactions().single.amount, 20000);
      await store.replaceAll(MoneySyncData([tx('same-id')], []));
      expect(store.transactions().single.amount, 20000);
      final tied = Tx.fromJson({...newer.toJson(), 'amount': 30000});
      await store.replaceAll(MoneySyncData([tied], []));
      expect(store.transactions().single.amount, 30000);
    },
  );
  test(
    'last cached user does not claim shared legacy financial records',
    () async {
      SharedPreferences.setMockInitialValues({
        AuthCache.userKey: 'bob',
        AuthCache.passwordKey: 'bob-old-password',
        BackendConfig.key: bob.backendUrl,
        MoneyStore.transactionsKey: jsonEncode([
          tx('alice-before-account-switch').toJson(),
        ]),
      });
      final legacy = await AuthCache.load();
      expect(legacy!.id, isEmpty);
      await expectLater(
        MoneyStore.load(session: legacy),
        throwsFormatException,
      );
      await AuthCache.save(bob);
      expect((await MoneyStore.load()).transactions(), isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getString(
          MoneyStore.transactionsKey,
        ),
        contains('alice-before-account-switch'),
      );
    },
  );
  test(
    'username-scoped encrypted snapshot is recoverable only by explicit confirmation',
    () async {
      final scope = sha256
          .convert(utf8.encode('server.example:3002\nalice'))
          .toString();
      final cipher = AesGcm.with256bits();
      final key = await cipher.newSecretKey();
      final box = await cipher.encrypt(
        utf8.encode(
          jsonEncode(
            MoneyStore.encodeData(MoneySyncData([tx('old-encrypted')], [])),
          ),
        ),
        secretKey: key,
        aad: utf8.encode(scope),
      );
      final raw = base64Encode(box.concatenation());
      await AuthCache.secure.write(
        key: 'money-manager-data-key-$scope',
        value: base64Encode(await key.extractBytes()),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('money-manager-encrypted-$scope', raw);
      await AuthCache.save(alice);
      final store = await MoneyStore.load();
      expect(store.transactions(), isEmpty);
      await expectLater(
        store.readRecoveryData(confirmed: false),
        throwsFormatException,
      );
      expect(
        (await store.readRecoveryData(confirmed: true)).transactions.single.id,
        'old-encrypted',
      );
      expect(prefs.getString('money-manager-encrypted-$scope'), raw);
    },
  );
  test(
    'stale logout and password response cannot clear or overwrite Bob session',
    () async {
      await AuthCache.save(bob);
      await AuthCache.signOutLocally(alice);
      expect((await AuthCache.load())!.id, bob.id);
      await expectLater(
        AuthCache.saveIfCurrent(alice, alice),
        throwsFormatException,
      );
      expect((await AuthCache.load())!.id, bob.id);
    },
  );
  test('sign out uses the rotated token of the same account', () async {
    final rotated = AuthSession(
      name: alice.name,
      backendUrl: alice.backendUrl,
      id: alice.id,
      token: 'rotated-token',
    );
    await AuthCache.save(rotated);
    await AuthCache.signOutLocally(alice);
    expect(await AuthCache.load(), isNull);
    expect((await AuthCache.pendingLogouts()).single.token, rotated.token);
  });
  testWidgets(
    'recovery requires confirmation and imports only selected records',
    (tester) async {
      await AuthCache.save(alice);
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode([
        {...tx('alice-old').toJson(), 'title': 'Alice lunch'},
        {...tx('bob-old').toJson(), 'title': 'Bob lunch'},
      ]);
      await prefs.setString(MoneyStore.transactionsKey, raw);
      final store = await MoneyStore.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountPage(
              store: store,
              transactions: [],
              recurring: [],
              session: alice,
              onReload: () async {},
              onLogout: () {},
              onChangePassword: (_, _, _) async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover older data'));
      await tester.pumpAndSettle();
      expect(find.text('Alice lunch'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.transactions(), isEmpty);
      await tester.tap(find.text('Recover older data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I am authorized'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Recover selected'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Alice lunch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover selected'));
      await tester.pumpAndSettle();
      expect(store.transactions().map((t) => t.id), ['alice-old']);
      expect(prefs.getString(MoneyStore.transactionsKey), raw);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'offline logout stays queued securely and is retried without losing current login',
    () async {
      await AuthCache.save(alice);
      await AuthCache.signOutLocally(alice);
      expect(await AuthCache.load(), isNull);
      await http.runWithClient(() async {
        expect(await AuthService.retryPendingLogouts(), 1);
      }, () => MockClient((_) async => http.Response('{}', 503)));
      await AuthCache.save(bob);
      await http.runWithClient(
        () async {
          expect(await AuthService.retryPendingLogouts(), 0);
        },
        () => MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer alice-token');
          expect(request.url.path, '/api/auth/logout');
          return http.Response('{"ok":true}', 200);
        }),
      );
      expect((await AuthCache.load())!.id, bob.id);
    },
  );
  test(
    'large sync uploads bounded batches and assembles revision-consistent pages',
    () async {
      final transactions = List.generate(
        2400,
        (i) => Tx.fromJson({
          ...tx('big-$i').toJson(),
          'note': 'x' * 2000,
          'title': 't' * 500,
        }),
      );
      var uploads = 0, uploaded = 0, downloads = 0;
      await http.runWithClient(
        () async {
          final result = await const MoneySyncService(
            session: alice,
          ).syncTwoWay(MoneySyncData(transactions, []));
          expect(result.transactions, hasLength(2400));
          expect(uploads, greaterThan(1));
          expect(uploaded, 2400);
          expect(downloads, 12);
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            expect(request.bodyBytes.length, lessThan(512 * 1024));
            final body = jsonDecode(request.body) as Map;
            expect(body['protocol'], 3);
            uploaded += (body['transactions'] as List).length;
            uploads++;
            return http.Response('{"ok":true,"protocol":3}', 200);
          }
          final cursor = int.parse(request.url.queryParameters['cursor']!);
          if (cursor != 0) {
            expect(request.url.queryParameters['revision'], 'a' * 64);
          }
          downloads++;
          return http.Response(
            jsonEncode({
              ...MoneyStore.encodeData(
                MoneySyncData(transactions.sublist(cursor, cursor + 200), []),
              ),
              'protocol': 3,
              'revision': 'a' * 64,
              'nextCursor': cursor + 200 == 2400 ? null : cursor + 200,
            }),
            200,
          );
        }),
      );
    },
  );
  test(
    'changed page revision restarts download instead of mixing snapshots',
    () async {
      var reads = 0;
      await http.runWithClient(
        () async {
          final result = await const MoneySyncService(
            session: alice,
          ).syncTwoWay(const MoneySyncData([], []));
          expect(result.transactions.map((t) => t.id), ['fresh']);
          expect(reads, 3);
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            return http.Response('{"ok":true,"protocol":3}', 200);
          }
          reads++;
          if (reads == 2) {
            return http.Response('{"message":"Data changed"}', 409);
          }
          return http.Response(
            jsonEncode({
              ...MoneyStore.encodeData(
                MoneySyncData([tx(reads == 1 ? 'stale' : 'fresh')], []),
              ),
              'protocol': 3,
              'revision': (reads == 1 ? 'a' : 'b') * 64,
              'nextCursor': reads == 1 ? 1 : null,
            }),
            200,
          );
        }),
      );
    },
  );
}
