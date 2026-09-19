import 'package:shared_preferences/shared_preferences.dart';

class BackendConfig {
  static const defaultUrl = 'http://192.168.1.142:3000';
  static const _key = 'vmc-backend-url';

  static Future<String> loadUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key)?.trim();
    final normalized = value == null || value.isEmpty ? defaultUrl : value;
    try {
      return _validate(normalized);
    } on FormatException {
      return defaultUrl;
    }
  }

  static Future<void> saveUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim().replaceAll(RegExp(r'/+$'), '');
    await prefs.setString(
      _key,
      _validate(normalized.isEmpty ? defaultUrl : normalized),
    );
  }

  static String _validate(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException(
        'Backend URL must be a valid http(s) URL without credentials.',
      );
    }
    return value;
  }
}
