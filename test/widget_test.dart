import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/app.dart';

void main() {
  testWidgets('app boots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const VietNamMapApp());
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });

  testWidgets('saved account opens directly after upgrading', (tester) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'traveler',
      'vmc-auth-password': 'secret1',
    });
    await tester.pumpWidget(const VietNamMapApp());
    await tester.pumpAndSettle();

    expect(find.text('Checkin'), findsOneWidget);
    expect(find.text('Create account'), findsNothing);
  });

  testWidgets('sign out keeps the account but requires sign in after restart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'traveler',
      'vmc-auth-password': 'secret1',
      'vmc-auth-session': true,
    });
    await tester.pumpWidget(const VietNamMapApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('vmc-auth-session'), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const VietNamMapApp());
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });
}
