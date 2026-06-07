import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checkin.dart';

class CheckInRepository {
  static const _storageKey = 'vnm_checkins';
  List<CheckIn>? _cache;

  Future<List<CheckIn>> load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _cache = decoded.map(CheckIn.fromJson).map(_repairLegacyItem).toList();
      await save(_cache!);
      return _cache!;
    }
    final seed = await rootBundle.loadString('assets/seeds/checkins_seed.json');
    final decoded = (jsonDecode(seed) as List).cast<Map<String, dynamic>>();
    _cache = decoded.map(CheckIn.fromJson).map(_repairLegacyItem).toList();
    await save(_cache!);
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
    await prefs.setString(_storageKey, jsonEncode(items.map((e) => e.toJson()).toList()));
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

  Future<void> markSynced(String id) async {
    final items = await load();
    final index = items.indexWhere((e) => e.id == id);
    if (index >= 0) {
      items[index] = items[index].copyWith(synced: true);
      await save(items);
    }
  }

}
