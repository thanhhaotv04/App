import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/checkin.dart';

class SyncService {
  const SyncService({this.baseUrl = 'http://127.0.0.1:3000'});

  final String baseUrl;

  bool get enabled => baseUrl.isNotEmpty;

  Future<List<CheckIn>> fetchRemote() async {
    if (!enabled) return [];
    final res = await http.get(Uri.parse('$baseUrl/api/checkins'));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
      return decoded.map(CheckIn.fromJson).toList();
    }
    throw Exception('Failed to fetch remote checkins');
  }

  Future<CheckIn> push(CheckIn item, {List<int>? photoBytes, String? photoFileName}) async {
    if (!enabled) return item;
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/checkins'))
      ..fields.addAll({
        'id': item.id,
        'city': item.city,
        'place': item.place,
        'notes': item.notes,
        'source': item.source,
        'synced': item.synced.toString(),
        'createdAt': item.createdAt.toString(),
        'lat': item.lat.toString(),
        'lng': item.lng.toString(),
        if (item.photo.isNotEmpty) 'photoPath': item.photo,
      });
    if (photoBytes != null && photoBytes.isNotEmpty) {
      request.files.add(http.MultipartFile.fromBytes('photo', photoBytes, filename: photoFileName ?? 'checkin-photo.jpg'));
    }
    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return CheckIn.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw Exception('Failed to push checkin: ${res.statusCode} ${res.body}');
  }

  Future<List<CheckIn>> syncTwoWay(List<CheckIn> localItems) async {
    if (!enabled) return localItems;
    final remoteBefore = await fetchRemote();
    final remoteIds = remoteBefore.map((e) => e.id).toSet();
    final pushed = <CheckIn>[];
    for (final item in localItems) {
      if (!remoteIds.contains(item.id)) {
        pushed.add(await push(item));
      }
    }
    final remoteAfter = await fetchRemote();
    final byId = <String, CheckIn>{};
    for (final item in [...remoteAfter, ...pushed, ...localItems]) {
      final current = byId[item.id];
      if (current == null || item.createdAt >= current.createdAt || item.photo.isNotEmpty) {
        byId[item.id] = item.copyWith(synced: true);
      }
    }
    final merged = byId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }
}
