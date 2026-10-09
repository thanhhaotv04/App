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
    final validated = _validate(normalized.isEmpty ? defaultUrl : normalized);
    // Bind sessions from older installs before changing the destination.
    if (!prefs.containsKey('vmc-auth-backend-origin') &&
        prefs.containsKey('vmc-auth-user')) {
      await prefs.setString('vmc-auth-backend-origin', origin(await loadUrl()));
    }
    await prefs.setString(_key, validated);
  }

  static String origin(String value) => Uri.parse(_validate(value)).origin;

  static String _validate(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException(
        'Backend URL must be a valid http(s) URL without credentials.',
      );
    }
    final octets = uri.host.split('.').map(int.tryParse).toList();
    final privateIpv4 =
        octets.length == 4 &&
        octets.every((part) => part != null && part >= 0 && part <= 255) &&
        (octets[0] == 10 ||
            octets[0] == 127 ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 172 && octets[1]! >= 16 && octets[1]! <= 31));
    if (uri.scheme == 'http' &&
        !privateIpv4 &&
        uri.host != 'localhost' &&
        uri.host != '::1') {
      throw const FormatException(
        'Use HTTPS for servers outside your trusted local network.',
      );
    }
    return value;
  }

  /// Private photo credentials may only be sent to the configured backend.
  static Uri photoUri(String baseUrl, String photo) {
    final base = Uri.parse(_validate(baseUrl));
    final uri = base.resolve(photo);
    final segments = uri.pathSegments;
    if (uri.origin != base.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        segments.length < 4 ||
        segments[0] != 'user' ||
        segments[1] != 'Picture' ||
        segments.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('/') ||
              part.contains('\\') ||
              part.runes.any((rune) => rune < 32),
        )) {
      throw const FormatException(
        'Photo must belong to the configured backend.',
      );
    }
    return uri;
  }
}
