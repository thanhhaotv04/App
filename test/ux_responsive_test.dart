import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/screens/history_screen.dart';
import 'package:vietnam_map_01/src/screens/settings_screen.dart';
import 'package:vietnam_map_01/src/repositories/privacy_settings.dart';
import 'package:vietnam_map_01/src/models/checkin.dart';
import 'package:vietnam_map_01/src/screens/insights_screen.dart';
import 'package:vietnam_map_01/src/screens/map_screen.dart';
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

  testWidgets('check-in keeps the primary add action on a narrow phone', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(360, 800),
      child: const MapScreen(checkinOnly: true),
    );

    expect(find.text('Check-in'), findsOneWidget);
    expect(find.byTooltip('Add a new check-in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map adapts to tablet and desktop widths', (tester) async {
    for (final size in [const Size(768, 1024), const Size(1440, 900)]) {
      await pumpScreen(tester, size: size, child: const MapScreen());

      expect(find.text('Vietnam map'), findsOneWidget);
      expect(find.text('Find memories'), findsNothing);
      expect(find.text('Recent memories'), findsNothing);
      expect(find.text('Click a province to check in'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('map includes the searchable check-in history', (tester) async {
    const item = CheckIn(
      id: 'trip-1',
      city: 'Lâm Đồng',
      place: 'Hồ Xuân Hương',
      notes: 'Walk by the lake',
      source: 'manual',
      synced: true,
      createdAt: 1700000000000,
      lat: 11.94,
      lng: 108.44,
      photo: '',
    );
    await pumpScreen(
      tester,
      size: const Size(1440, 900),
      child: const MapScreen(),
      preferences: {
        'vmc-auth-user': 'tester',
        'vnm_checkins_user_${base64UrlEncode(utf8.encode('tester'))}':
            jsonEncode([item.toJson()]),
      },
    );

    expect(find.text('Check-in history'), findsOneWidget);
    expect(find.text('Hồ Xuân Hương'), findsOneWidget);
    expect(find.text('Search memories'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('check-in form has a quick path and optional details', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      size: const Size(360, 800),
      child: const MapScreen(checkinOnly: true),
    );

    await tester.tap(find.byTooltip('Add a new check-in'));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('New check-in'), findsOneWidget);
    expect(find.text('Photos and details'), findsOneWidget);
    expect(find.text('Choose photos'), findsOneWidget);
    expect(find.text('Province / City'), findsOneWidget);
    expect(find.text('Tags'), findsNothing);
    expect(find.text('Favorite place'), findsNothing);
    expect(find.text('Memory score'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'insights fit a narrow mobile layout with only requested sections',
    (tester) async {
      await pumpScreen(
        tester,
        size: const Size(320, 568),
        child: const InsightsScreen(),
      );

      expect(find.text('Travel insights'), findsOneWidget);
      expect(find.text('Vietnam coverage'), findsOneWidget);
      expect(find.text('Wishlist'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('map history shows an actionable empty state', (tester) async {
    await pumpScreen(
      tester,
      size: const Size(640, 360),
      child: const HistoryScreen(),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pump();
    expect(find.text('Start your travel story'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'privacy switches save immediately and account controls fit large text',
    (tester) async {
      for (final width in [375.0, 768.0, 1024.0, 1440.0]) {
        await pumpScreen(
          tester,
          size: Size(width, 900),
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Local only'),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Local only'));
        await tester.pumpAndSettle();
        expect((await PrivacySettings.load()).localOnly, isTrue);
        await tester.scrollUntilVisible(
          find.text('Hide exact coordinates'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Hide exact coordinates'));
        await tester.pumpAndSettle();
        expect((await PrivacySettings.load()).hideLocation, isTrue);
        expect(find.text('Save privacy'), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Check for update'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
}
