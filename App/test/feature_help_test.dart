import 'package:esp32_navride/src/feature_help.dart';
import 'package:esp32_navride/src/fleet_marker_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Main marker help does not change the photo option', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var changes = 0;
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FleetMarkerControls(
            active: true,
            busy: false,
            photo: false,
            onPhotoChanged: (_) => changes++,
            onSave: (_) => saves++,
          ),
        ),
      ),
    );
    final help = find.byTooltip('Help about Markers');
    expect(find.byTooltip('Help about Take a photo'), findsNothing);
    expect(
      tester.getSemantics(help).getSemanticsData().tooltip,
      'Help about Markers',
    );
    expect(tester.getSize(help).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(help).height, greaterThanOrEqualTo(48));
    expect(find.textContaining('photos are compressed'), findsNothing);
    await tester.tap(help);
    await tester.pumpAndSettle();
    expect(find.textContaining('photos are compressed'), findsOneWidget);
    expect(changes, 0);
    expect(saves, 0);
    await tester.tap(find.byTooltip('Close help'));
    await tester.pumpAndSettle();
    expect(find.textContaining('photos are compressed'), findsNothing);
    await tester.tap(help);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('photos are compressed'), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final width in [320.0, 375.0, 768.0, 1440.0]) {
    testWidgets('Help scrolls at $width with 200% text and closes on Escape', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeatureHelp(
              title: 'Trips',
              message: 'Help for a longer feature description.\n\n' * 30,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Help about Trips'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });
  }
}
