import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:esp32_navride/src/app.dart';
import 'package:esp32_navride/src/models.dart';
import 'package:esp32_navride/src/storage.dart';
import 'package:esp32_navride/src/update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const navigationChannel = MethodChannel('esp32_navride/navigation');
const snapshotKey = 'esp32-navride.snapshot.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'recover valid records and connection without losing the original data',
    () async {
      final raw = jsonEncode({
        'notices': [
          {'id': 'good', 'title': 'Keep me'},
          42,
        ],
        'tasks': [
          {'id': 'bad', 'done': 'false'},
          {'id': 'good', 'title': 'Keep task'},
        ],
        'config': {'mode': 'bluetooth', 'bluetoothId': 'saved-board'},
      });
      SharedPreferences.setMockInitialValues({snapshotKey: raw});
      final storage = NavRideStorage();
      final data = await storage.load();
      expect(data.notices.single.title, 'Keep me');
      expect(data.tasks.single.title, 'Keep task');
      expect(data.config.bluetoothId, 'saved-board');
      expect(storage.recoveryWarning, isNotNull);
      final prefs = await SharedPreferences.getInstance();
      final backup = prefs.getKeys().singleWhere(
        (key) => key.startsWith('$snapshotKey.recovery.'),
      );
      expect(prefs.getString(backup), raw);
      await storage.save(data);
      expect((await NavRideStorage().load()).tasks.single.title, 'Keep task');
      expect(prefs.getString(backup), raw);
    },
  );

  test('unreadable JSON cannot be silently loaded or overwritten', () async {
    const raw = '{broken';
    SharedPreferences.setMockInitialValues({snapshotKey: raw});
    await expectLater(NavRideStorage().load(), throwsFormatException);
    await expectLater(
      NavRideStorage().save(
        const NavRideSnapshot(
          profileName: 'You',
          notices: [],
          tasks: [],
          config: NavRideConfig(),
        ),
      ),
      throwsFormatException,
    );
    expect((await SharedPreferences.getInstance()).getString(snapshotKey), raw);
  });

  testWidgets(
    'Wi-Fi failure clears status and periodic health recovers it without locking buttons',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        snapshotKey: jsonEncode({
          'notices': [
            {'id': 'wifi', 'title': 'Test', 'body': 'Message'},
          ],
          'config': {
            'mode': 'network',
            'baseUrl': 'http://192.168.1.55',
            'pairingPin': '123456',
          },
        }),
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        navigationChannel,
        (_) async => <String, bool>{},
      );
      var online = true;
      var healthCalls = 0;
      final delayedHealth = Completer<http.Response>();
      final client = MockClient((request) async {
        if (request.url.path == '/api/health' && ++healthCalls == 2) {
          return delayedHealth.future;
        }
        if (!online) throw http.ClientException('Network disconnected');
        return http.Response(
          request.url.path == '/api/health'
              ? '{"connected":true,"mode":"wifi"}'
              : '{"ok":true}',
          200,
        );
      });
      try {
        await http.runWithClient(() async {
          await tester.pumpWidget(const NavRideApp());
          await tester.pumpAndSettle();
          expect(find.text('Connected · Wi-Fi'), findsOneWidget);
          await tester.pump(const Duration(seconds: 3));
          await tester.pump();
          online = false;
          await tester.tap(find.text('Content').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('menu-notice-wifi')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Send to display'));
          await tester.pumpAndSettle();
          // A health response begun before the failed send must not restore stale status.
          delayedHealth.complete(
            http.Response('{"connected":true,"mode":"wifi"}', 200),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Navigation').last);
          await tester.pumpAndSettle();
          expect(find.text('Connected · Wi-Fi'), findsNothing);
          online = true;
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(find.text('Connected · Wi-Fi'), findsOneWidget);
          online = false;
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(find.text('Connected · Wi-Fi'), findsNothing);
          expect(
            tester
                .widget<IconButton>(
                  find.widgetWithIcon(IconButton, Icons.refresh),
                )
                .onPressed,
            isNotNull,
          );
        }, () => client);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          navigationChannel,
          null,
        );
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'retry connection reports native errors and releases the busy state',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        snapshotKey: jsonEncode({
          'config': {'mode': 'bluetooth', 'bluetoothId': 'saved-board'},
        }),
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        navigationChannel,
        (call) async {
          if (call.method == 'getOsmAndBridgeStatus') {
            return {
              'configured': true,
              'notificationAccess': true,
              'listenerConnected': false,
              'osmandInstalled': true,
              'ready': false,
            };
          }
          if (call.method == 'recoverNavigationConnection') {
            throw PlatformException(
              code: 'recovery_failed',
              message: 'Recovery failed. Try again.',
            );
          }
          return null;
        },
      );
      try {
        await tester.pumpWidget(const NavRideApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('navigation-primary')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Recovery failed. Try again.'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('navigation-primary')),
              )
              .onPressed,
          isNotNull,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          navigationChannel,
          null,
        );
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  for (final accept in [false, true]) {
    testWidgets('shortened BLE content requires consent: $accept', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final body = 'Message'.padRight(80, '!');
      SharedPreferences.setMockInitialValues({
        snapshotKey: jsonEncode({
          'notices': [
            {'id': 'long', 'title': 'Reminder'.padRight(40, '!'), 'body': body},
          ],
          'config': {'mode': 'bluetooth', 'bluetoothId': 'saved-board'},
        }),
      });
      Map<String, dynamic>? sent;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        navigationChannel,
        (call) async {
          if (call.method == 'getOsmAndBridgeStatus') {
            return {
              'configured': true,
              'bleConnected': true,
              'popupCommandConfirmed': sent != null,
            };
          }
          if (call.method == 'sendBleCommand') {
            sent =
                jsonDecode((call.arguments as Map)['payload'] as String)
                    as Map<String, dynamic>;
            return true;
          }
          return null;
        },
      );
      try {
        await tester.pumpWidget(const NavRideApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Content').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('menu-notice-long')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send to display'));
        await tester.pumpAndSettle();
        expect(sent, isNull);
        expect(find.text('Message is too long for Bluetooth'), findsOneWidget);
        await tester.tap(find.text(accept ? 'Send shorter version' : 'Cancel'));
        await tester.pumpAndSettle();
        if (accept) {
          expect((sent!['body'] as String).length, lessThan(80));
          expect(find.text('ESP32 confirmed delivery.'), findsOneWidget);
        } else {
          expect(sent, isNull);
          expect(find.text('ESP32 confirmed delivery.'), findsNothing);
        }
        expect((await NavRideStorage().load()).notices.single.body, body);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          navigationChannel,
          null,
        );
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  test(
    'reuse verified APK after permission failure; redownload tampered cache',
    () async {
      final cache = await Directory.systemTemp.createTemp(
        'navride-update-regression-',
      );
      const channel = MethodChannel('esp32_navride/update');
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var permission = false;
      var downloads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getCacheDirectory') return cache.path;
            if (call.method == 'installApk' && !permission) {
              throw PlatformException(code: 'install_failed');
            }
            return null;
          });
      final bytes = [0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4];
      final service = AppUpdateService(
        baseUrl: 'http://192.168.1.55:3000',
        client: MockClient((_) async {
          downloads++;
          return http.Response.bytes(bytes, 200);
        }),
      );
      final info = UpdateInfo(
        available: true,
        versionName: 'test',
        versionCode: 2,
        apkUrl: 'http://192.168.1.55:3000/releases/app.apk',
        notes: '',
        sha256Digest: sha256.convert(bytes).toString(),
        sizeBytes: bytes.length,
      );
      try {
        final path = await service.downloadApk(info);
        await expectLater(
          service.installApk(path),
          throwsA(isA<PlatformException>()),
        );
        permission = true;
        await service.installApk(await service.downloadApk(info));
        expect(downloads, 1);
        await File(path).writeAsBytes([0, 0, 0, 0, 0, 0, 0, 0]);
        await service.downloadApk(info);
        expect(downloads, 2);
        expect(await File(path).readAsBytes(), bytes);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await cache.delete(recursive: true);
      }
    },
  );
}
