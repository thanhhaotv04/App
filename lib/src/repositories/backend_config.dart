import 'package:shared_preferences/shared_preferences.dart';

class BackendConfig {
  static const defaultUrl = 'http://192.168.1.157:3000';
  static const _key = 'vmc-backend-url';

  static Future<String> loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key)?.trim();
    return value == null || value.isEmpty ? defaultUrl : value;
  }

  static Future<void> saveUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(_key, normalized.isEmpty ? defaultUrl : normalized);
  }
}
