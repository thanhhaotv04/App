import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/app_version.dart';
import 'package:vietnam_map_01/src/models/checkin.dart';
import 'package:vietnam_map_01/src/repositories/checkin_repository.dart';
import 'package:vietnam_map_01/src/screens/insights_screen.dart';
import 'package:vietnam_map_01/src/screens/settings_screen.dart';

void main() {
  Future<void> pumpAtLargeSize(WidgetTester tester, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pumpAndSettle();
  }

  testWidgets('insights exposes only the four requested sections', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpAtLargeSize(tester, const InsightsScreen());

    for (final title in [
      'Vietnam coverage',
      'Progress by 8 regions',
      'Travel rhythm',
      'Travel recap',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Wishlist'), findsNothing);
    expect(find.text('Achievements'), findsNothing);
    expect(find.text('Portable backup'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('travel rhythm labels fit below a populated month bar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'rhythm-user'});
    await CheckInRepository().save([
      CheckIn(
        id: 'trip-1',
        city: 'Lâm Đồng',
        place: 'Hồ Xuân Hương',
        notes: '',
        source: 'manual',
        synced: false,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        lat: 0,
        lng: 0,
        photo: '',
      ),
    ]);
    await pumpAtLargeSize(tester, const InsightsScreen());

    expect(find.text('1 active check-in days'), findsOneWidget);
    expect(find.text('Travel rhythm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account retains credentials, theme, sync and update controls', (
    tester,
  ) async {
    var signedOut = false;
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'existing-user',
      'vmc-auth-password': 'existing-password',
    });
    await pumpAtLargeSize(
      tester,
      SettingsScreen(onSignOut: () => signedOut = true),
    );

    expect(find.text('Account'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'existing-user',
      ),
      findsOneWidget,
    );
    expect(find.text('Current password'), findsOneWidget);
    expect(find.text('Change password'), findsOneWidget);
    expect(find.text('New password'), findsNothing);
    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Toggle theme'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Check for update'), findsOneWidget);
    expect(
      find.text(
        'Current version v${AppVersion.versionName} (build ${AppVersion.versionCode})',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Sign out'));
    expect(signedOut, isTrue);
    expect(find.text('Delete all check-ins'), findsNothing);
    expect(find.text('Restore JSON'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
