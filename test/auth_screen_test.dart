import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/screens/auth_gate.dart';

void main() {
  testWidgets('new users register explicitly and can switch to sign in', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    final submitted = <AuthMode>[];
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          hasAccount: false,
          onSubmit: (mode, name, password) async {
            submitted.add(mode);
            expect(name, 'Traveler');
            expect(password, 'secret123');
            return mode == AuthMode.register
                ? 'This user name is already registered.'
                : null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    expect(find.text('Backend URL'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'User name'),
      'Traveler',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'secret123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'different',
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords do not match.'), findsOneWidget);
    expect(submitted, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm password'),
      'secret123',
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(submitted, [AuthMode.register]);
    expect(find.text('This user name is already registered.'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vmc-backend-url'), isNull);

    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm password'), findsNothing);
    expect(find.text('Create account'), findsNothing);
    final signInButton = find.widgetWithText(FilledButton, 'Sign in');
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
    await tester.pumpAndSettle();
    expect(submitted, [AuthMode.register, AuthMode.signIn]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved accounts start on sign in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: AuthScreen(
          hasAccount: true,
          onSubmit: (mode, name, password) async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Confirm password'), findsNothing);
    expect(find.text('Backend URL'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
