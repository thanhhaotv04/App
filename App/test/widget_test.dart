import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esp32_navride/src/app.dart';
import 'package:esp32_navride/src/storage.dart';
import 'package:esp32_navride/src/transport.dart';

const navigationChannel = MethodChannel('esp32_navride/navigation');

void testApp(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'preserves the previous snapshot key and starts new installs empty',
    () async {
      final empty = await NavRideStorage().load();
      expect(empty.notices, isEmpty);
      expect(empty.tasks, isEmpty);
      SharedPreferences.setMockInitialValues({
        'esp32-monitor.snapshot.v1':
            '{"profileName":"Hào","notices":[],"tasks":[],"config":{"background":"forest","updateBaseUrl":"http://192.168.1.149:3000"}}',
      });
      final snapshot = await NavRideStorage().load();
      expect(snapshot.profileName, 'Hào');
      expect(snapshot.config.updateBaseUrl, 'http://192.168.1.149:3000');
      await NavRideStorage().save(snapshot);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('esp32-navride.snapshot.v1'),
        contains('"profileName":"Hào"'),
      );
      expect(
        prefs.getString('esp32-navride.snapshot.v1'),
        isNot(contains('background')),
      );
    },
  );

  test(
    'offline preview never reports successful delivery or connection',
    () async {
      final preview = DemoTransport();
      expect((await preview.health()).connected, isFalse);
      await expectLater(
        preview.send({'command': 'push_notification'}),
        throwsStateError,
      );
      await expectLater(preview.setupWifi('test', 'test'), throwsStateError);
    },
  );

  testApp('has three destinations, no fake device, profile or color picker', (
    tester,
  ) async {
    await tester.pumpWidget(const NavRideApp());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Active'), findsNothing);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Connect ESP32'), findsOneWidget);
    expect(find.text('App background'), findsNothing);
    expect(find.text('User profile'), findsNothing);
    expect(find.byKey(const ValueKey('update-server-url')), findsNothing);
  });

  testApp('opens optional update settings and saves a normalized URL', (
    tester,
  ) async {
    await tester.pumpWidget(const NavRideApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('App updates'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('App updates'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('update-server-url')),
      '192.168.1.149:3000',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('check-app-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-app-update')));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('esp32-navride.snapshot.v1'),
      contains('"updateBaseUrl":"http://192.168.1.149:3000"'),
    );
    expect(
      find.text('Server saved. Install updates on your Android phone.'),
      findsOneWidget,
    );
  });

  testApp(
    'validates, saves and completes content without automatically sending',
    (tester) async {
      await tester.pumpWidget(const NavRideApp());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Content').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-content')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a title.'), findsOneWidget);
      expect(find.text('Enter a message.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'Đi đổ xăng');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'Trước khi khởi hành',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Đi đổ xăng'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.tap(find.text('Tasks'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-content')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Kiểm tra xe');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      final data =
          jsonDecode(prefs.getString('esp32-navride.snapshot.v1')!)
              as Map<String, dynamic>;
      expect((data['tasks'] as List).single['done'], isTrue);
      expect((data['notices'] as List).single['title'], 'Đi đổ xăng');
    },
  );

  testApp('deletion can be undone and offline send is disabled', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'esp32-navride.snapshot.v1': jsonEncode({
        'profileName': 'Hào',
        'notices': [
          {'id': 'n1', 'title': 'Đừng quên áo mưa', 'body': 'Trong cốp xe'},
        ],
        'tasks': [],
        'config': {},
      }),
    });
    await tester.pumpWidget(const NavRideApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Content').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('menu-notice-n1')));
    await tester.pumpAndSettle();
    final send = find.widgetWithText(PopupMenuItem<String>, 'Send to display');
    expect(tester.widget<PopupMenuItem<String>>(send).enabled, isFalse);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Đừng quên áo mưa'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Đừng quên áo mưa'), findsOneWidget);
  });

  testApp(
    'native status, open OsmAnd and confirmed sample use the same bridge',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'esp32-navride.snapshot.v1': jsonEncode({
          'profileName': 'Hào',
          'notices': [],
          'tasks': [],
          'config': {'mode': 'bluetooth', 'bluetoothId': 'saved-board'},
        }),
      });
      var connected = true;
      var confirmed = false;
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        navigationChannel,
        (call) async {
          calls.add(call);
          if (call.method == 'getOsmAndBridgeStatus') {
            return {
              'configured': true,
              'notificationAccess': true,
              'osmandInstalled': true,
              'ready': true,
              'aidlSubscribed': true,
              'bleConnected': connected,
              'osmandDataRecent': false,
              'lastNavigationConfirmed': confirmed,
            };
          }
          if (call.method == 'sendOsmAndSample') {
            confirmed = true;
            return true;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          navigationChannel,
          null,
        ),
      );
      await tester.pumpWidget(const NavRideApp());
      await tester.pumpAndSettle();
      expect(find.text('Ready for directions'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('navigation-primary')));
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'openOsmAnd'), hasLength(1));
      await tester.scrollUntilVisible(find.text('Test display'), 250);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test display'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('navigation-sample-left')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('navigation-sample-left')));
      await tester.pumpAndSettle();
      final sample = calls.singleWhere(
        (call) => call.method == 'sendOsmAndSample',
      );
      expect(sample.arguments, {
        'maneuver': 'left',
        'distanceMeters': 250,
        'streetName': 'Nguyen Hue',
      });
      expect(
        find.text('ESP32 received the 250 m navigation sample.'),
        findsOneWidget,
      );
      connected = false;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Ready for directions'), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('navigation-sample-left')),
            )
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testApp(
    'stopped listener offers access repair instead of claiming readiness',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        'esp32-navride.snapshot.v1': jsonEncode({
          'notices': [],
          'tasks': [],
          'config': {'mode': 'bluetooth', 'bluetoothId': 'saved-board'},
        }),
      });
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        navigationChannel,
        (call) async {
          calls.add(call.method);
          if (call.method == 'getOsmAndBridgeStatus') {
            return {
              'configured': true,
              'notificationAccess': true,
              'listenerConnected': false,
              'osmandInstalled': true,
              'bleConnected': true,
              'ready': false,
            };
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          navigationChannel,
          null,
        ),
      );
      await tester.pumpWidget(const NavRideApp());
      await tester.pumpAndSettle();
      expect(find.text('Restore notification access'), findsOneWidget);
      expect(find.text('Ready for directions'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('navigation-primary')));
      await tester.pumpAndSettle();
      expect(calls, contains('openNotificationAccessSettings'));
      expect(calls, isNot(contains('openOsmAnd')));
    },
  );

  testApp('Settings reconnect actually restarts the configured native bridge', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({
      'esp32-navride.snapshot.v1': jsonEncode({
        'notices': [],
        'tasks': [],
        'config': {'mode': 'bluetooth', 'bluetoothId': 'saved-board'},
      }),
    });
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      navigationChannel,
      (call) async {
        calls.add(call);
        if (call.method == 'getOsmAndBridgeStatus') {
          return {
            'configured': true,
            'notificationAccess': true,
            'listenerConnected': true,
          };
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        navigationChannel,
        null,
      ),
    );
    await tester.pumpWidget(const NavRideApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reconnect'));
    await tester.tap(find.text('Reconnect'));
    await tester.pumpAndSettle();
    final reconnects = calls.where(
      (call) => call.method == 'configureOsmAndBridge',
    );
    expect(reconnects, hasLength(1));
    expect((reconnects.single.arguments as Map)['deviceId'], 'saved-board');
  });

  for (final acknowledged in [true, false]) {
    testApp(
      'native notification success requires a firmware ACK: $acknowledged',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        SharedPreferences.setMockInitialValues({
          'esp32-navride.snapshot.v1': jsonEncode({
            'notices': [
              {'id': 'test', 'title': 'Rẽ phải', 'body': 'Nguyễn Huệ'},
            ],
            'tasks': [],
            'config': {'mode': 'bluetooth', 'bluetoothId': 'saved-board'},
          }),
        });
        Map<String, dynamic>? payload;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          navigationChannel,
          (call) async {
            if (call.method == 'getOsmAndBridgeStatus') {
              return {
                'configured': true,
                'bleConnected': true,
                'popupCommandConfirmed': payload != null && acknowledged,
              };
            }
            if (call.method == 'sendBleCommand') {
              payload =
                  jsonDecode((call.arguments as Map)['payload'] as String)
                      as Map<String, dynamic>;
              return true;
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            navigationChannel,
            null,
          ),
        );
        await tester.pumpWidget(const NavRideApp());
        await tester.pumpAndSettle();
        await tester.tap(find.text('Content').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('menu-notice-test')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send to display'));
        await tester.pump();
        if (!acknowledged) {
          for (var i = 0; i < 26; i++) {
            await tester.pump(const Duration(milliseconds: 200));
          }
        }
        await tester.pumpAndSettle();
        expect(payload?['title'], 'Re phai');
        expect(payload?['requestId'], isA<int>());
        expect(
          find.text('ESP32 confirmed delivery.'),
          acknowledged ? findsOneWidget : findsNothing,
        );
        if (!acknowledged) {
          expect(
            find.text(
              'No confirmation from ESP32. Check the connection and try again.',
            ),
            findsOneWidget,
          );
        }
      },
    );
  }

  for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
    testApp('layout fits width $width and enlarged text', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(const NavRideApp());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Content').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Settings').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('mode-bluetooth')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
