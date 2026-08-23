import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

class LocalImageStorage {
  static const _prefix = 'local:web:';
  static const _storagePrefix = 'vnm_web_image_';
  static const _userKey = 'vmc-auth-user';

  static bool isLocalRef(String value) => value.startsWith(_prefix);

  static Future<String> saveImage({
    required List<int> bytes,
    required String originalName,
    required String city,
    required int createdAt,
  }) async {
    if (bytes.isEmpty) return '';
    final prefs = await SharedPreferences.getInstance();
    final account = await _accountToken(prefs);
    final fileToken = base64UrlEncode(
      utf8.encode(
        '$createdAt-${DateTime.now().microsecondsSinceEpoch}-$originalName',
      ),
    );
    final key = '$_storagePrefix${account}_$fileToken';
    await prefs.setString(key, base64Encode(bytes));
    return '$_prefix$key';
  }

  static Future<Uint8List?> readImage(String ref) async {
    if (!isLocalRef(ref)) return null;
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(ref.substring(_prefix.length));
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteImage(String ref) async {
    if (!isLocalRef(ref)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ref.substring(_prefix.length));
  }

  static Future<void> deleteAllImages({bool allUsers = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = allUsers
        ? _storagePrefix
        : '$_storagePrefix${await _accountToken(prefs)}_';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      await prefs.remove(key);
    }
  }

  static Future<void> moveUserData(String oldName, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final oldPrefix = '$_storagePrefix${_accountTokenFor(oldName)}_';
    final newPrefix = '$_storagePrefix${_accountTokenFor(newName)}_';
    for (final oldKey in prefs.getKeys().where(
      (key) => key.startsWith(oldPrefix),
    )) {
      final newKey = '$newPrefix${oldKey.substring(oldPrefix.length)}';
      final value = prefs.getString(oldKey);
      if (value != null && prefs.getString(newKey) == null) {
        await prefs.setString(newKey, value);
      }
      await prefs.remove(oldKey);
    }
  }

  static Future<String> folderPath() async {
    return 'Local image folder is only available on Android and Windows builds.';
  }

  static Future<String> _accountToken(SharedPreferences prefs) async {
    return _accountTokenFor(prefs.getString(_userKey)?.trim() ?? 'local');
  }

  static String _accountTokenFor(String name) => base64UrlEncode(
    utf8.encode(
      name.trim().toLowerCase().isEmpty ? 'local' : name.trim().toLowerCase(),
    ),
  );
}
