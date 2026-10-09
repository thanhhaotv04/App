import 'dart:convert';

import 'package:esp32_navride/src/app.dart';
import 'package:esp32_navride/src/storage.dart';
import 'package:esp32_navride/src/transport.dart';
import 'package:esp32_navride/src/update_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const snapshotKey = 'esp32-navride.snapshot.v1';
const channel = MethodChannel('esp32_navride/navigation');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local HTTP works; public HTTP and credential URLs are rejected', () {
    for (final host in [
      '192.168.1.55',
      '10.0.0.1',
      '172.16.0.1',
      '172.31.255.254',
      '169.254.1.1',
      '127.0.0.1',
      'esp32.local',
      '[::1]',
      '[fd12::1]',
      '[fe80::1]',
    ]) {
      expect(normalizeEsp32BaseUrl('http://$host'), startsWith('http://'));
      expect(normalizeUpdateBaseUrl('http://$host'), startsWith('http://'));
    }
    for (final host in [
      'example.com',
      '8.8.8.8',
      '172.15.1.1',
      '172.32.1.1',
      '192.168.1.999',
      'esp32.local.example.com',
      '[2001:db8::1]',
    ]) {
      expect(
        () => normalizeEsp32BaseUrl('http://$host'),
        throwsFormatException,
      );
      expect(
        () => normalizeUpdateBaseUrl('http://$host'),
        throwsFormatException,
      );
    }
    expect(
      normalizeEsp32BaseUrl('https://device.example.com'),
      startsWith('https://'),
    );
    expect(
      () => normalizeEsp32BaseUrl('https://user:secret@example.com'),
      throwsFormatException,
    );
  });

  test('redirects cannot forward PIN, content or Wi-Fi credentials', () async {
    for (final operation in ['health', 'content', 'wifi']) {
      var requests = 0;
      final transport = NetworkTransport(
        '192.168.1.55',
        pairingPin: '123456',
        client: MockClient((request) async {
          requests++;
          expect(request.followRedirects, isFalse);
          expect(request.headers['x-navride-pin'], '123456');
          return http.Response(
            '',
            307,
            headers: {'location': 'https://other.example.com'},
          );
        }),
      );
      await expectLater(switch (operation) {
        'health' => transport.health(),
        'content' => transport.send({
          'command': 'push_notification',
          'body': 'Private note',
        }),
        _ => transport.setupWifi('Private network', 'private-password'),
      }, throwsFormatException);
      expect(requests, 1);
    }
  });

  test(
    'delete removes current, legacy and recovery data without resurrection',
    () async {
      SharedPreferences.setMockInitialValues({
        snapshotKey: '{broken',
        'esp32-monitor.snapshot.v1': 'legacy content',
        '$snapshotKey.recovery.1': 'private recovery data',
        '$snapshotKey.recovery.2': 'private recovery data',
        'other-setting': 'keep',
      });
      await NavRideStorage().clear();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'other-setting'});
      final loaded = await NavRideStorage().load();
      expect(loaded.notices, isEmpty);
      expect(loaded.tasks, isEmpty);
      expect(loaded.config.bluetoothId, isEmpty);
      expect(loaded.config.pairingPin, isEmpty);
    },
  );

  for (final choice in ['cancel', 'delete', 'native-failure']) {
    testWidgets('privacy deletion: $choice', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final raw = jsonEncode({
        'profileName': 'Private rider',
        'notices': [
          {'id': 'private', 'title': 'Private note', 'body': 'Saved content'},
        ],
        'tasks': [
          {'id': 'task', 'title': 'Private task'},
        ],
        'config': {
          'mode': 'bluetooth',
          'bluetoothId': 'saved-board',
          'pairingPin': '123456',
        },
      });
      SharedPreferences.setMockInitialValues({
        snapshotKey: raw,
        'esp32-monitor.snapshot.v1': raw,
        '$snapshotKey.recovery.1': raw,
      });
      var cleared = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'clearLocalData') {
          if (choice == 'native-failure') {
            throw PlatformException(code: 'clear_failed');
          }
          cleared = true;
          return true;
        }
        if (call.method == 'getOsmAndBridgeStatus') {
          return {'configured': !cleared, 'bleConnected': !cleared};
        }
        return <String, dynamic>{};
      });
      try {
        await tester.pumpWidget(const NavRideApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Privacy and data'), 300);
        await tester.tap(find.text('Privacy and data'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('clear-local-data')),
          300,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('clear-local-data')));
        await tester.pumpAndSettle();
        expect(cleared, isFalse);
        await tester.tap(
          find.text(choice == 'cancel' ? 'Cancel' : 'Delete data'),
        );
        await tester.pumpAndSettle();
        final prefs = await SharedPreferences.getInstance();
        if (choice == 'delete') {
          expect(cleared, isTrue);
          expect(prefs.getKeys(), isEmpty);
          await tester.tap(find.text('Content').last);
          await tester.pumpAndSettle();
          expect(find.text('Private note'), findsNothing);
          expect(find.text('No notifications yet'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('add-content')));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Title'),
            'New note',
          );
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Content'),
            'New content',
          );
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect((await NavRideStorage().load()).profileName, 'You');
        } else {
          expect(prefs.getString(snapshotKey), raw);
          if (choice == 'native-failure') {
            expect(
              find.text('Could not delete all data. Please try again.'),
              findsOneWidget,
            );
            expect(
              tester
                  .widget<OutlinedButton>(
                    find.byKey(const ValueKey('clear-local-data')),
                  )
                  .onPressed,
              isNotNull,
            );
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('pairing PIN is masked and hidden again when app backgrounds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
    try {
      await tester.pumpWidget(const NavRideApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mode-network')));
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('device-pairing-pin'));
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.enterText(field, '12ab3456');
      expect(tester.widget<TextField>(field).controller!.text, '123456');
      await tester.tap(find.byTooltip('Show PIN'));
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'edit saved content retains identity, completion and due date at 375px',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      SharedPreferences.setMockInitialValues({
        snapshotKey: jsonEncode({
          'notices': [
            {
              'id': 'note',
              'title': 'Old title',
              'body': 'Old body',
              'priority': 'high',
            },
          ],
          'tasks': [
            {
              'id': 'task',
              'title': 'Old task',
              'done': true,
              'dueAt': '2026-10-09T08:00:00',
            },
          ],
        }),
      });
      try {
        await tester.pumpWidget(const NavRideApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Content').last);
        await tester.pumpAndSettle();
        for (final task in [false, true]) {
          if (task) {
            await tester.tap(find.text('Tasks').first);
            await tester.pumpAndSettle();
          }
          await tester.tap(
            find.byKey(ValueKey(task ? 'menu-task-task' : 'menu-notice-note')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextFormField, task ? 'Task name' : 'Title'),
            task ? 'Updated task' : 'Updated title',
          );
          if (!task) {
            await tester.enterText(
              find.widgetWithText(TextFormField, 'Content'),
              'Updated body',
            );
          }
          await tester.tap(find.text('Save'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final snapshot = await NavRideStorage().load();
        expect(snapshot.notices.single.id, 'note');
        expect(snapshot.notices.single.body, 'Updated body');
        expect(snapshot.notices.single.priority, 'high');
        expect(snapshot.tasks.single.id, 'task');
        expect(snapshot.tasks.single.title, 'Updated task');
        expect(snapshot.tasks.single.done, isTrue);
        expect(snapshot.tasks.single.dueAt, DateTime(2026, 10, 9, 8));
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
