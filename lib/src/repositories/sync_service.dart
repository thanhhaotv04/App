import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checkin.dart';
import 'auth_service.dart';

class SyncService {
  const SyncService({
    this.baseUrl = 'http://127.0.0.1:3000',
    this.userName,
    this.password,
  });

  final String baseUrl;
  final String? userName;
  final String? password;

  bool get enabled => baseUrl.isNotEmpty;

  static const _userKey = 'vmc-auth-user';
  static const _passwordKey = 'vmc-auth-password';

  Future<(String, String)> _credentials() async {
    final cachedUser = userName?.trim();
    final cachedPassword = password;
    if (cachedUser != null &&
        cachedUser.isNotEmpty &&
        cachedPassword != null &&
        cachedPassword.isNotEmpty) {
      return (cachedUser, cachedPassword);
    }
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString(_userKey)?.trim() ?? '';
    final storedPassword = prefs.getString(_passwordKey) ?? '';
    if (storedUser.isEmpty || storedPassword.isEmpty) {
      throw Exception('Sign in before syncing with the backend.');
    }
    return (storedUser, storedPassword);
  }

  Future<Map<String, String>> _authHeaders() async {
    final (name, pass) = await _credentials();
    return {'X-User-Name': name, 'X-Password': pass};
  }

  Future<void> _ensureBackendAccount() async {
    final (name, pass) = await _credentials();
    final auth = AuthService(baseUrl: baseUrl);
    try {
      await auth.login(name, pass);
    } on AuthException catch (err) {
      if (err.statusCode == 404) {
        await auth.register(name, pass);
        return;
      }
      rethrow;
    }
  }

  Future<List<CheckIn>> fetchRemote() async {
    if (!enabled) return [];
    await _ensureBackendAccount();
    final res = await http.get(
      Uri.parse('$baseUrl/api/checkins'),
      headers: await _authHeaders(),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final decoded = (jsonDecode(res.body) as List)
          .cast<Map<String, dynamic>>();
      return decoded.map(CheckIn.fromJson).toList();
    }
    throw Exception('Failed to fetch remote checkins');
  }

  Future<CheckIn> push(
    CheckIn item, {
    List<int>? photoBytes,
    String? photoFileName,
  }) async {
    if (!enabled) return item;
    await _ensureBackendAccount();
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/api/checkins'))
          ..headers.addAll(await _authHeaders())
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
            'favorite': item.favorite.toString(),
            'rating': item.rating.toString(),
            'tags': jsonEncode(item.tags),
            if (item.photo.isNotEmpty) 'photoPath': item.photo,
          });
    if (photoBytes != null && photoBytes.isNotEmpty) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          photoBytes,
          filename: photoFileName ?? 'checkin-photo.jpg',
        ),
      );
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
      if (current == null ||
          item.createdAt >= current.createdAt ||
          item.photo.isNotEmpty) {
        byId[item.id] = item.copyWith(synced: true);
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  Future<void> deleteCheckIn(String id) async {
    if (!enabled) return;
    await _ensureBackendAccount();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/checkins/$id'),
      headers: await _authHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to delete check-in: ${response.statusCode}');
    }
  }

  Future<CheckIn> deletePhoto(String id) async {
    if (!enabled) throw Exception('Backend sync is disabled.');
    await _ensureBackendAccount();
    final response = await http.delete(
      Uri.parse('$baseUrl/api/checkins/$id/photo'),
      headers: await _authHeaders(),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return CheckIn.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to delete photo: ${response.statusCode}');
  }
}
