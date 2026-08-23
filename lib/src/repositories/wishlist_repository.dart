import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores provinces a traveller wants to visit without changing check-in data.
class WishlistRepository {
  static const _storageKey = 'vnm_wishlist';

  Future<Set<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet();
      }
    } catch (_) {
      // Ignore an invalid old wishlist and start with an empty one.
    }
    return <String>{};
  }

  Future<void> save(Iterable<String> provinces) async {
    final values =
        provinces
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(values));
  }
}
