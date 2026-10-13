import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_navride/src/fleet_marker_controls.dart';

void main() {
  testWidgets('Markers need a trip, not a Bluetooth connection', (
    tester,
  ) async {
    String? selected;
    Future<void> show(bool active, {bool busy = false}) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FleetMarkerControls(
            active: active,
            busy: busy,
            photo: false,
            onPhotoChanged: (_) {},
            onSave: (kind) => selected = kind,
          ),
        ),
      ),
    );
    await show(false);
    await tester.tap(find.text('Food'));
    expect(selected, isNull);
    expect(find.textContaining('Start a Fleet trip'), findsOneWidget);
    await show(true);
    for (final kind in ['save_point', 'food', 'danger']) {
      await tester.tap(find.byKey(ValueKey('marker-$kind')));
      expect(selected, kind);
    }
    await show(true, busy: true);
    selected = null;
    await tester.tap(find.text('Danger'));
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Controls wrap on narrow screens and large text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SizedBox(
                width: 280,
                child: FleetMarkerControls(
                  active: true,
                  busy: false,
                  photo: true,
                  onPhotoChanged: (_) {},
                  onSave: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Take a photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
