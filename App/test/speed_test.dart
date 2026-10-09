import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esp32_navride/src/app.dart';

void main() {
  const channel = MethodChannel('esp32_navride/navigation');
  for (final denied in [false, true]) {
    testWidgets('GPS opt-in, unknown speed and permission denial: $denied', (
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
      var running = false;
      int? kmh;
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        switch (call.method) {
          case 'getOsmAndBridgeStatus':
            return {
              'configured': true,
              'bleConnected': true,
              'notificationAccess': true,
              'listenerConnected': true,
              'osmandInstalled': true,
              'ready': true,
            };
          case 'getSpeedStatus':
            return {
              'running': running,
              'kmh': kmh,
              'message': 'Waiting for GPS',
              // A heartbeat with unknown speed can still be acknowledged.
              'delivered': running,
            };
          case 'startSpeed':
            if (denied) {
              throw PlatformException(
                code: 'location_denied',
                message: 'Allow precise location.',
              );
            }
            running = true;
            return true;
          case 'stopSpeed':
            running = false;
            return true;
          default:
            return null;
        }
      });
      try {
        await tester.pumpWidget(const NavRideApp());
        await tester.pumpAndSettle();
        expect(calls, isNot(contains('startSpeed')));
        final toggle = find.byKey(const ValueKey('gps-speed-toggle'));
        await tester.scrollUntilVisible(toggle, 300);
        await tester.pumpAndSettle();
        expect(find.text('-- km/h'), findsOneWidget);
        expect(find.textContaining('Speed limit'), findsNothing);
        await tester.tap(toggle);
        await tester.pumpAndSettle(const Duration(milliseconds: 500));
        if (denied) {
          expect(find.text('Allow precise location.'), findsOneWidget);
          expect(running, isFalse);
        } else {
          expect(find.text('Stop GPS speed'), findsOneWidget);
          expect(find.text('-- km/h'), findsOneWidget); // no fix is NOT 0
          expect(find.textContaining('ESP32 receiving'), findsNothing);
          kmh = 0;
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
          expect(find.text('0 km/h'), findsOneWidget);
          expect(find.textContaining('ESP32 receiving'), findsOneWidget);
          await tester.tap(toggle);
          await tester.pumpAndSettle(const Duration(milliseconds: 500));
          expect(calls, contains('stopSpeed'));
          expect(find.text('-- km/h'), findsOneWidget);
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
}
