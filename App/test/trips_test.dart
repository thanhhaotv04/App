import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_navride/src/fleet_tracking_panel.dart';
import 'package:esp32_navride/src/fleet_marker_list.dart';
import 'package:esp32_navride/src/fleet_trip_history.dart';

const channel = MethodChannel('esp32_navride/navigation');

void main() {
  testWidgets(
    'Trip history does not read the page scroll offset as expanded state',
    (tester) async {
      final storage = PageStorageBucket();
      var loads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getFleetTrips') {
          loads++;
          if (loads == 2) throw PlatformException(code: 'offline');
          return [
            {
              'id': 'trip-1',
              'startedAt': '2026-10-13T01:00:00Z',
              'endedAt': '2026-10-13T02:00:00Z',
            },
          ];
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageStorage(
              bucket: storage,
              child: ListView(
                key: const PageStorageKey('trips-page'),
                children: [
                  Builder(
                    builder: (context) {
                      // A previously scrolled Trips page already has a saved double offset.
                      storage.writeState(context, 120.0);
                      return const FleetTripHistory();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Recent trips'));
      await tester.pumpAndSettle();
      expect(loads, 1);
      expect(find.textContaining('Ended ·'), findsOneWidget);
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('History unavailable.'), findsOneWidget);
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(find.textContaining('Ended ·'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Private ride starts without BLE/Firebase and never opts in to Fleet',
    (tester) async {
      var running = false;
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'getSpeedStatus') {
          return {'running': running, 'delivered': false};
        }
        if (call.method == 'getFleetStatus') return {'active': false};
        if (call.method == 'startRide') {
          running = true;
          return true;
        }
        if (call.method == 'endRide') {
          running = false;
          return true;
        }
        return null;
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FleetTrackingPanel(
                enabled: false,
                trips: true,
                rideAvailable: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false,
      );
      await tester.tap(find.text('Start ride'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      final start = calls.singleWhere((c) => c.method == 'startRide');
      expect(start.arguments, {'shareFleet': false});
      expect(find.text('End ride'), findsOneWidget);
      expect(
        find.text('Private ride · location is not shared with Fleet.'),
        findsOneWidget,
      );
      await tester.tap(find.text('End ride'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'endRide'), hasLength(1));
      expect(find.text('Start ride'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );

  testWidgets('GPS denial is actionable and never shows an active ride', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'getSpeedStatus') return {'running': false};
      if (call.method == 'getFleetStatus') return {'active': false};
      if (call.method == 'startRide') {
        throw PlatformException(
          code: 'location_denied',
          message: 'Allow precise location and try again.',
        );
      }
      return null;
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FleetTrackingPanel(
              enabled: false,
              trips: true,
              rideAvailable: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start ride'));
    await tester.pumpAndSettle();
    expect(find.text('Allow precise location and try again.'), findsOneWidget);
    expect(find.text('Ride off'), findsOneWidget);
    expect(find.text('End ride'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    );
  });

  testWidgets(
    'Marker edit saves note/type and deletion requires confirmation',
    (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (call.method == 'getFleetMarkers') {
          return {
            'items': [
              {
                'id': 'own',
                'kind': 'food',
                'note': 'Lunch',
                'status': 'Saved on phone',
                'editable': true,
                'hasPhoto': false,
              },
              {
                'id': 'other',
                'kind': 'danger',
                'note': '',
                'status': 'Synced',
                'editable': false,
                'hasPhoto': true,
              },
            ],
          };
        }
        return true;
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: FleetMarkerList())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Saved on phone'), findsOneWidget);
      expect(find.text('Synced'), findsOneWidget);
      expect(find.text('Edit'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Good food');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        calls.singleWhere((c) => c.method == 'editFleetMarker').arguments,
        {'id': 'own', 'kind': 'food', 'note': 'Good food'},
      );
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'deleteFleetMarker'), isEmpty);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete marker'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'deleteFleetMarker'), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    },
  );

  for (final width in [320.0, 768.0]) {
    testWidgets('Trips and marker states fit $width with large text', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'getFleetMarkers') {
          return {
            'items': [
              for (final status in [
                'Uploading',
                'Upload failed',
                'Saved on phone',
                'Synced',
              ])
                {
                  'id': status,
                  'kind': 'save_point',
                  'note': 'Long note ' * 30,
                  'status': status,
                  'editable': true,
                },
            ],
          };
        }
        return null;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SingleChildScrollView(
                child: Column(
                  children: const [
                    FleetTrackingPanel(enabled: false, trips: true),
                    FleetMarkerList(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });
  }
}
