import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps server credentials out of SharedPreferences while preserving the
/// existing offline sign-in behavior with a salted, one-way verifier.
class CredentialStore {
  const CredentialStore();

  static const userKey = 'vmc-auth-user';
  static const legacyPasswordKey = 'vmc-auth-password';
  static const _verifierKey = 'vmc-auth-verifier';
  static const _tokenKey = 'vmc-auth-token';
  static const _tokenFallbackKey = 'vmc-auth-token-fallback';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  Future<void> saveSession({
    required String userName,
    required String password,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(userKey, userName.trim());
    await prefs.setString(_verifierKey, _newVerifier(password));
    await prefs.remove(legacyPasswordKey);
    await writeToken(token);
  }

  Future<bool> matchesOffline(String userName, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString(userKey)?.trim() ?? '';
    if (storedUser.toLowerCase() != userName.trim().toLowerCase()) return false;
    final verifier = prefs.getString(_verifierKey);
    if (verifier != null && verifier.isNotEmpty) {
      return _matchesVerifier(password, verifier);
    }
    // One-release migration path for installs that stored a plain password.
    final legacy = prefs.getString(legacyPasswordKey);
    if (legacy != password) return false;
    await prefs.setString(_verifierKey, _newVerifier(password));
    await prefs.remove(legacyPasswordKey);
    return true;
  }

  Future<bool> hasOfflineAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(userKey)?.trim() ?? '';
    return user.isNotEmpty &&
        ((prefs.getString(_verifierKey)?.isNotEmpty ?? false) ||
            (prefs.getString(legacyPasswordKey)?.isNotEmpty ?? false));
  }

  Future<String> readToken() async {
    try {
      return await _secure.read(key: _tokenKey) ?? '';
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenFallbackKey) ?? '';
    }
  }

  Future<void> writeToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (token.isEmpty) {
        await _secure.delete(key: _tokenKey);
      } else {
        await _secure.write(key: _tokenKey, value: token);
      }
      await prefs.remove(_tokenFallbackKey);
    } catch (_) {
      if (token.isEmpty) {
        await prefs.remove(_tokenFallbackKey);
      } else {
        // Test/desktop fallback. Native Android/iOS builds use secure storage.
        await prefs.setString(_tokenFallbackKey, token);
      }
    }
  }

  Future<Map<String, String>> authHeaders({
    String? userName,
    String? migrationPassword,
    String? token,
  }) async {
    final resolvedToken = token?.trim().isNotEmpty == true
        ? token!.trim()
        : await readToken();
    if (resolvedToken.isNotEmpty) {
      return {'Authorization': 'Bearer $resolvedToken'};
    }
    final prefs = await SharedPreferences.getInstance();
    final name = userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : prefs.getString(userKey)?.trim() ?? '';
    final legacyPassword =
        migrationPassword ?? prefs.getString(legacyPasswordKey) ?? '';
    if (name.isEmpty || legacyPassword.isEmpty) {
      throw StateError('Sign in again before syncing with the backend.');
    }
    return {'X-User-Name': name, 'X-Password': legacyPassword};
  }

  Future<void> clearToken() => writeToken('');

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await clearToken();
    await prefs.remove(userKey);
    await prefs.remove(legacyPasswordKey);
    await prefs.remove(_verifierKey);
    await prefs.remove(_tokenFallbackKey);
  }

  Future<String> readSecret(String key) async {
    try {
      return await _secure.read(key: key) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> writeSecret(String key, String value) async {
    try {
      if (value.isEmpty) {
        await _secure.delete(key: key);
      } else {
        await _secure.write(key: key, value: value);
      }
    } catch (_) {
      throw StateError('Secure storage is unavailable on this device.');
    }
  }

  static String _newVerifier(String password) {
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final digest = sha256.convert([...salt, ...utf8.encode(password)]).bytes;
    return '${base64UrlEncode(salt)}:${base64UrlEncode(digest)}';
  }

  static bool _matchesVerifier(String password, String verifier) {
    final parts = verifier.split(':');
    if (parts.length != 2) return false;
    try {
      final salt = base64Url.decode(parts[0]);
      final expected = base64Url.decode(parts[1]);
      final actual = sha256.convert([...salt, ...utf8.encode(password)]).bytes;
      if (actual.length != expected.length) return false;
      var difference = 0;
      for (var index = 0; index < actual.length; index += 1) {
        difference |= actual[index] ^ expected[index];
      }
      return difference == 0;
    } catch (_) {
      return false;
    }
  }
}
