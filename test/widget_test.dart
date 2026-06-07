import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/app.dart';

void main() {
  testWidgets('app boots', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const VietNamMapApp());
    await tester.pumpAndSettle();
    expect(find.text('Create and sign in'), findsOneWidget);
  });
}
