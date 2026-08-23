import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checkin.dart';

class CheckInRepository {
  static const _legacyStorageKey = 'vnm_checkins';
  static const _storagePrefix = 'vnm_checkins_user_';
  static const _legacyOwnerKey = 'vnm_checkins_legacy_owner';
  static const _userKey = 'vmc-auth-user';

  CheckInRepository({this.userName});

  final String? userName;
  List<CheckIn>? _cache;
  String? _cacheKey;

  Future<List<CheckIn>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _storageKeyFor(prefs);
    if (_cache != null && _cacheKey == key) return _cache!;
    final raw = await _readRaw(prefs, key);
    if (raw != null && raw.isNotEmpty) {
      final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _cache = decoded.map(CheckIn.fromJson).map(_repairLegacyItem).toList();
      _cacheKey = key;
      await _saveTo(prefs, key, _cache!);
      return _cache!;
    }
    final seed = await rootBundle.loadString('assets/seeds/checkins_seed.json');
    final decoded = (jsonDecode(seed) as List).cast<Map<String, dynamic>>();
    _cache = decoded.map(CheckIn.fromJson).map(_repairLegacyItem).toList();
    _cacheKey = key;
    await _saveTo(prefs, key, _cache!);
    return _cache!;
  }

  CheckIn _repairLegacyItem(CheckIn item) {
    final city = _repairText(item.city);
    final place = _repairText(item.place);
    final notes = _repairText(item.notes);
    final photo = _repairText(item.photo);
    return item.copyWith(city: city, place: place, notes: notes, photo: photo);
  }

  String _repairText(String value) {
    return value
        .replaceAll('TP.Há»“ ChÃ­ Minh', 'TP.Hồ Chí Minh')
        .replaceAll('BÃ¬nh Äá»‹nh', 'Bình Định')
        .replaceAll('Nghá»‡ An', 'Nghệ An')
        .replaceAll('Check-in táº¡i', 'Check-in in');
  }

  Future<void> save(List<CheckIn> items) async {
    _cache = List.of(items);
    final prefs = await SharedPreferences.getInstance();
    final key = _storageKeyFor(prefs);
    _cacheKey = key;
    await _saveTo(prefs, key, _cache!);
  }

  Future<void> add(CheckIn item) async {
    final items = await load();
    items.insert(0, item);
    await save(items);
  }

  Future<void> remove(String id) async {
    final items = await load();
    items.removeWhere((e) => e.id == id);
    await save(items);
  }

  Future<void> update(CheckIn item) async {
    final items = await load();
    final index = items.indexWhere((entry) => entry.id == item.id);
    if (index < 0) {
      items.insert(0, item);
    } else {
      items[index] = item;
    }
    await save(items);
  }

  Future<void> updateAll(List<CheckIn> items) => save(items);

  Future<void> deletePhoto(String id) async {
    final items = await load();
    final index = items.indexWhere((entry) => entry.id == id);
    if (index < 0) return;
    items[index] = items[index].withoutPhoto();
    await save(items);
  }

  Future<void> markSynced(String id) async {
    final items = await load();
    final index = items.indexWhere((e) => e.id == id);
    if (index >= 0) {
      items[index] = items[index].copyWith(synced: true);
      await save(items);
    }
  }

  /// Moves local records when the account username is changed in Settings.
  static Future<void> moveUserData(String oldName, String newName) async {
    final oldKey = _keyForName(oldName);
    final newKey = _keyForName(newName);
    if (oldKey == newKey) return;
    final prefs = await SharedPreferences.getInstance();
    final oldRaw = prefs.getString(oldKey);
    if (oldRaw != null && prefs.getString(newKey) == null) {
      await prefs.setString(newKey, oldRaw);
    }
    final owner = prefs.getString(_legacyOwnerKey)?.trim() ?? '';
    if (_sameUser(owner, oldName)) {
      await prefs.setString(_legacyOwnerKey, newName.trim());
    }
    await prefs.remove(oldKey);
  }

  /// Clears only the current account's local check-ins.
  static Future<void> clearCurrentData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString(_userKey)?.trim() ?? '';
    final owner = prefs.getString(_legacyOwnerKey)?.trim() ?? '';
    if (user.isEmpty || owner.isEmpty || _sameUser(owner, user)) {
      await prefs.remove(_legacyStorageKey);
    }
    if (user.isNotEmpty) {
      await prefs.remove(_keyForName(user));
      if (_sameUser(owner, user)) {
        await prefs.remove(_legacyOwnerKey);
      }
    }
  }

  /// Clears every account-scoped local check-in key on this device.
  static Future<void> clearAllData() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
      (key) => key == _legacyStorageKey || key.startsWith(_storagePrefix),
    );
    for (final key in keys.toList()) {
      await prefs.remove(key);
    }
    await prefs.remove(_legacyOwnerKey);
  }

  String _storageKeyFor(SharedPreferences prefs) {
    final explicit = userName?.trim() ?? '';
    final current = explicit.isNotEmpty
        ? explicit
        : (prefs.getString(_userKey)?.trim() ?? '');
    return current.isEmpty ? _legacyStorageKey : _keyForName(current);
  }

  Future<String?> _readRaw(SharedPreferences prefs, String key) async {
    final scoped = prefs.getString(key);
    if (scoped != null && scoped.isNotEmpty) return scoped;
    if (key == _legacyStorageKey) return scoped;

    // Migrate an old unscoped store once, assigning it to the first known
    // account. A different username will never inherit it afterwards.
    final legacy = prefs.getString(_legacyStorageKey);
    if (legacy == null || legacy.isEmpty) return null;
    final user = userName?.trim() ?? prefs.getString(_userKey)?.trim() ?? '';
    final owner = prefs.getString(_legacyOwnerKey)?.trim() ?? '';
    if (user.isEmpty || (owner.isNotEmpty && !_sameUser(owner, user))) {
      return null;
    }
    await prefs.setString(_legacyOwnerKey, user);
    await prefs.setString(key, legacy);
    return legacy;
  }

  Future<void> _saveTo(
    SharedPreferences prefs,
    String key,
    List<CheckIn> items,
  ) async {
    await prefs.setString(
      key,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static String _keyForName(String name) {
    final normalized = name.trim().toLowerCase();
    return '$_storagePrefix${base64UrlEncode(utf8.encode(normalized))}';
  }

  static bool _sameUser(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();
}
