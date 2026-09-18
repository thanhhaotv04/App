import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vietnam_map_01/src/screens/home_shell.dart';

void main() {
  testWidgets('five requested destinations fit and navigate on a phone', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: '/checkin',
      routes: [
        ShellRoute(
          builder: (context, state, child) => HomeShell(child: child),
          routes: [
            for (final route in [
              '/checkin',
              '/album',
              '/map',
              '/insights',
              '/account',
            ])
              GoRoute(
                path: route,
                builder: (context, state) => Center(child: Text(route)),
              ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    for (final entry in [
      ('Album', '/album'),
      ('Map', '/map'),
      ('Insights', '/insights'),
      ('Account', '/account'),
      ('Checkin', '/checkin'),
    ]) {
      await tester.tap(find.text(entry.$1));
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
