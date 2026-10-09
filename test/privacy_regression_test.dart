import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:money_manager/src/app.dart';
import 'package:money_manager/src/models.dart';
import 'package:money_manager/src/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    MoneyManagerApp.hideAmounts.value = false;
    MoneyManagerApp.themeMode.value = ThemeMode.light;
  });

  test(
    'legacy local passwords upgrade without losing data; password changes require ownership',
    () async {
      final salt = List<int>.filled(16, 7);
      final hash = await (await Pbkdf2.hmacSha256(
        iterations: 120000,
        bits: 256,
      ).deriveKeyFromPassword(password: '1234', nonce: salt)).extractBytes();
      final accountKey =
          '${AuthCache.offlineAccountPrefix}${sha256.convert(utf8.encode('owner'))}';
      await AuthCache.secure.write(
        key: accountKey,
        value: jsonEncode({
          'name': 'owner',
          'salt': base64Encode(salt),
          'hash': base64Encode(hash),
        }),
      );
      final session = await AuthCache.signInOffline('owner', '1234');
      final store = await MoneyStore.load();
      await store.addExpense(
        Tx(
          id: 'saved',
          title: 'Private purchase',
          category: 'Food',
          amount: 45000,
          date: DateTime(2026, 10, 8),
        ),
      );
      final upgraded =
          jsonDecode((await AuthCache.secure.read(key: accountKey))!) as Map;
      expect(upgraded['iterations'], 600000);
      expect(upgraded['hash'], isNot(base64Encode(hash)));
      await expectLater(
        AuthCache.updateOfflinePassword(
          session: session,
          currentPassword: 'wrong',
          newPassword: 'new-private-password',
        ),
        throwsFormatException,
      );
      await AuthCache.updateOfflinePassword(
        session: session,
        currentPassword: '1234',
        newPassword: 'new-private-password',
      );
      await AuthCache.clear();
      await expectLater(
        AuthCache.signInOffline('owner', '1234'),
        throwsFormatException,
      );
      final signed = await AuthCache.signInOffline(
        'OWNER',
        'new-private-password',
      );
      expect(signed.id, session.id);
      expect((await MoneyStore.load()).transactions().single.id, 'saved');
      await AuthCache.registerOffline('another', 'another-private-password');
      await expectLater(
        AuthCache.updateOfflinePassword(
          session: session,
          currentPassword: 'new-private-password',
          newPassword: 'unauthorized-password',
        ),
        throwsFormatException,
      );
      await expectLater(
        AuthCache.registerOffline('weak', '1234'),
        throwsFormatException,
      );
    },
  );

  test(
    'local login throttles repeated guesses and allows retry after expiry',
    () async {
      await AuthCache.registerOffline('owner', 'local-private-password');
      await AuthCache.clear();
      for (var i = 0; i < 10; i++) {
        await expectLater(
          AuthCache.signInOffline('owner', 'wrong'),
          throwsFormatException,
        );
      }
      await expectLater(
        AuthCache.signInOffline('OWNER', 'local-private-password'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('five minutes'),
          ),
        ),
      );
      final accountKey =
          '${AuthCache.offlineAccountPrefix}${sha256.convert(utf8.encode('owner'))}';
      final saved =
          jsonDecode((await AuthCache.secure.read(key: accountKey))!)
              as Map<String, dynamic>;
      saved['lockedUntil'] = DateTime.now().millisecondsSinceEpoch - 1;
      await AuthCache.secure.write(key: accountKey, value: jsonEncode(saved));
      expect(
        (await AuthCache.signInOffline('owner', 'local-private-password')).name,
        'owner',
      );
      expect(
        jsonDecode((await AuthCache.secure.read(key: accountKey))!),
        isNot(contains('failedAttempts')),
      );
    },
  );

  testWidgets(
    'sync sign-in remains reachable without sending local financial data',
    (tester) async {
      const local = AuthSession(
        name: 'owner',
        id: 'offline-11111111-1111-4111-8111-111111111111',
        backendUrl: BackendConfig.offlineUrl,
      );
      await AuthCache.save(local);
      final store = await MoneyStore.load();
      await store.addExpense(
        Tx(
          id: 'local-only',
          title: 'Local private purchase',
          category: 'Food',
          amount: 45000,
          date: DateTime(2026, 10, 8),
        ),
      );
      await AuthCache.clear();
      final paths = <String>[];
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const MoneyManagerApp());
          await tester.pumpAndSettle();
          await tester.tap(find.text('Use a sync account'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField).first, 'owner');
          await tester.enterText(
            find.byType(TextField).last,
            'server-private-password',
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
          await tester.pumpAndSettle();
        },
        () => MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'name': 'owner',
              'id': 'server-owner-id',
              'token': 'a' * 64,
            }),
            200,
          );
        }),
      );
      expect(paths, ['/api/auth/login']);
      expect((await AuthCache.load())!.id, 'server-owner-id');
      expect((await MoneyStore.load()).transactions(), isEmpty);
      expect(
        (await MoneyStore.load(session: local)).transactions().single.id,
        'local-only',
      );
    },
  );

  testWidgets('sync password recovery submits a code and returns to sign-in', (
    tester,
  ) async {
    List<String>? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, _) async => null,
          onRegister: (_, _) async => null,
          onServerLogin: (_, _) async => null,
          onServerRegister: (_, _) async => null,
          onResetPassword: (name, password, code) async {
            submitted = [name, password, code];
            return null;
          },
        ),
      ),
    );
    await tester.tap(find.text('Use a sync account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'owner');
    await tester.enterText(fields.at(1), 'new-private-password');
    await tester.enterText(fields.at(2), 'new-private-password');
    await tester.enterText(fields.at(3), 'a' * 64);
    final submit = find.widgetWithText(FilledButton, 'Reset password');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(submitted, ['owner', 'new-private-password', 'a' * 64]);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(
      find.text('Password reset. Sign in with your new password.'),
      findsOneWidget,
    );
  });

  testWidgets('sync server settings reject insecure URLs and save HTTPS', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          onLogin: (_, _) async => null,
          onRegister: (_, _) async => null,
          onServerLogin: (_, _) async => null,
          onServerRegister: (_, _) async => null,
          onResetPassword: (_, _, _) async => null,
        ),
      ),
    );
    await tester.tap(find.text('Use a sync account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Server settings'));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'http://192.0.2.1:3002');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use HTTPS'), findsOneWidget);
    await tester.enterText(field, 'https://sync.example:3002/');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await BackendConfig.loadUrl(), 'https://sync.example:3002');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'local registration is usable on a narrow screen with large text',
    (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthScreen(
            onLogin: (_, _) async => null,
            onRegister: (_, _) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Register'));
      await tester.pumpAndSettle();
      final submit = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(submit);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hidden amounts persist, leave input usable and cover inactive screens',
    (tester) async {
      tester.view.physicalSize = const Size(465, 1024);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const session = AuthSession(
        name: 'owner',
        id: 'owner-id',
        token: 'owner-token',
        backendUrl: 'https://server.example',
      );
      await AuthCache.save(session);
      final store = await MoneyStore.load();
      await store.addExpense(
        Tx(
          id: 'private',
          title: 'Private purchase',
          category: 'Food',
          amount: 45000,
          date: DateTime(2026, 10, 8),
        ),
      );
      await tester.pumpWidget(const MoneyManagerApp(now: null));
      await tester.pumpAndSettle();
      expect(find.textContaining('45,000'), findsWidgets);
      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();
      expect(find.textContaining('45,000'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          MoneyManagerApp.hideAmountsKey,
        ),
        isTrue,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('privacy-cover')), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('privacy-cover')), findsNothing);
      expect(find.byTooltip('Show amounts'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Add'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('4'));
      await tester.tap(find.text('000'));
      await tester.pump();
      expect(find.text('VND 4,000'), findsOneWidget);
      await tester.tap(find.byTooltip('Show amounts'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('45,000'),
        findsNothing,
      ); // The add form stays selected.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Overview'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('45,000'), findsWidgets);
    },
  );

  testWidgets(
    'local account exposes password settings; all tabs support large text',
    (tester) async {
      const session = AuthSession(
        name: 'owner',
        id: 'offline-11111111-1111-4111-8111-111111111111',
        backendUrl: BackendConfig.offlineUrl,
      );
      await AuthCache.save(session);
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MoneyManagerApp());
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      for (final tab in ['Overview', 'Add', 'History', 'Account']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(tab),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab with large text');
      }
      final password = find.text('Change password');
      await tester.scrollUntilVisible(
        password,
        250,
        scrollable: find
            .descendant(
              of: find.byType(AccountPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(password);
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Update Password'),
        findsOneWidget,
      );
      expect((await AuthCache.load())!.id, session.id);
      expect(tester.takeException(), isNull);
    },
  );
}
