import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/screens/history_screen.dart';
import 'package:vietnam_map_01/src/screens/insights_screen.dart';
import 'package:vietnam_map_01/src/screens/map_screen.dart';
import 'package:vietnam_map_01/src/screens/sync_screen.dart';
import 'package:vietnam_map_01/src/theme/app_theme.dart';

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required Size size,
    required Widget child,
    Map<String, Object> preferences = const {},
  }) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues(preferences);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('map keeps the primary add action on a narrow phone', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(360, 800),
      child: const MapScreen(),
    );

    expect(find.text('Vietnam map'), findsOneWidget);
    expect(find.byTooltip('Add a new check-in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map adapts to tablet and desktop widths', (tester) async {
    for (final size in [const Size(768, 1024), const Size(1440, 900)]) {
      await pumpScreen(tester, size: size, child: const MapScreen());

      expect(find.text('Find memories'), findsOneWidget);
      expect(find.text('Recent memories'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('check-in form has a quick path and optional details', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(360, 800),
      child: const MapScreen(),
    );

    await tester.tap(find.byTooltip('Add a new check-in'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('New check-in'), findsOneWidget);
    expect(find.text('Add memory details'), findsOneWidget);
    expect(find.text('Province / City'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'insights fit a narrow mobile layout with an empty-state action',
    (tester) async {
      await pumpScreen(
        tester,
        size: const Size(320, 568),
        child: const InsightsScreen(),
      );

      expect(find.text('Travel insights'), findsOneWidget);
      expect(find.text('Start your travel story'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history and sync show actionable empty and device states', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(640, 360),
      child: const HistoryScreen(),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pump();
    expect(find.text('Start your travel story'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await pumpScreen(
      tester,
      size: const Size(1024, 768),
      child: const SyncScreen(),
      preferences: const {'vmc-backend-url': 'http://127.0.0.1:3000'},
    );
    expect(find.text('Sync & backend'), findsOneWidget);
    expect(find.text('Using a phone?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
