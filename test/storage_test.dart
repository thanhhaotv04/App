import 'package:flutter_test/flutter_test.dart';
import 'package:money_manager/src/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('uses the configured LAN sync endpoint by default', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await BackendConfig.loadUrl(), 'http://192.168.1.141:3002');
  });

  test(
    'migrates the recovered localhost endpoint to the LAN endpoint',
    () async {
      SharedPreferences.setMockInitialValues({
        BackendConfig.key: BackendConfig.legacyDefaultUrl,
      });

      expect(await BackendConfig.loadUrl(), BackendConfig.defaultUrl);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BackendConfig.key), BackendConfig.defaultUrl);
    },
  );
}
