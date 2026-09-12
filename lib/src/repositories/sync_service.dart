import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checkin.dart';
import 'auth_service.dart';
import 'local_image_storage.dart';

class PhotoUpload {
  const PhotoUpload({required this.bytes, required this.fileName});

  final List<int> bytes;
  final String fileName;
}

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
    List<PhotoUpload>? photoUploads,
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
            'album': item.album,
            'photos': jsonEncode(
              item.photoItems
                  .map(
                    (entry) => {
                      'photo': entry.photo,
                      'name': entry.name,
                      'createdAt': entry.createdAt,
                    },
                  )
                  .toList(),
            ),
            if (item.photo.isNotEmpty) 'photoPath': item.photo,
          });
    if (photoUploads != null) {
      for (final upload in photoUploads) {
        if (upload.bytes.isEmpty) continue;
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            upload.bytes,
            filename: upload.fileName,
          ),
        );
      }
    } else {
      final pendingAssets = item.photoItems
          .where((entry) => entry.photo.isEmpty && entry.localPhoto.isNotEmpty)
          .toList();
      if (photoBytes != null && photoBytes.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            photoBytes,
            filename: photoFileName ?? 'checkin-photo.jpg',
          ),
        );
      }
      final assetsToRead = photoBytes != null && photoBytes.isNotEmpty
          ? pendingAssets.skip(1)
          : pendingAssets;
      for (final asset in assetsToRead) {
        final bytes = await LocalImageStorage.readImage(asset.localPhoto);
        if (bytes == null || bytes.isEmpty) continue;
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            bytes,
            filename: asset.name.isEmpty ? 'checkin-photo.jpg' : asset.name,
          ),
        );
      }
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
    final remoteById = {for (final item in remoteBefore) item.id: item};
    final localById = {for (final item in localItems) item.id: item};
    final pushed = <String, CheckIn>{};
    for (final item in localItems) {
      final remote = remoteById[item.id];
      final shouldPush =
          remote == null ||
          !item.synced ||
          (item.localPhoto.isNotEmpty && (remote.photo.isEmpty));
      if (shouldPush) {
        final uploaded = await push(item);
        pushed[item.id] = mergeLocalPhotos(
          uploaded.copyWith(synced: true),
          item,
        );
      }
    }
    final remoteAfter = await fetchRemote();
    final byId = <String, CheckIn>{};
    for (final remote in remoteAfter) {
      final local = localById[remote.id];
      if (local != null && local.photoItems.isNotEmpty) {
        byId[remote.id] = mergeLocalPhotos(
          remote.copyWith(synced: true),
          local,
        );
      } else {
        byId[remote.id] = await _hydrateRemotePhoto(remote);
      }
    }
    for (final local in localItems) {
      final uploaded = pushed[local.id];
      if (uploaded != null) {
        byId[local.id] = uploaded;
        continue;
      }
      final remote = byId[local.id];
      if (remote == null) {
        // This is only reachable if the backend accepted a write but did not
        // return the item on the subsequent read. Keep the local record for a
        // later retry instead of dropping it.
        byId[local.id] = local;
        continue;
      }
      if (remote.photo != local.photo && local.localPhoto.isNotEmpty) {
        await LocalImageStorage.deleteImage(local.localPhoto);
      }
      byId[local.id] = mergeLocalPhotos(remote.copyWith(synced: true), local);
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  Future<CheckIn> _hydrateRemotePhoto(CheckIn item) async {
    if (item.photo.isEmpty || item.localPhoto.isNotEmpty) {
      return item.copyWith(synced: true);
    }
    try {
      final response = await http.get(
        _photoUri(item.photo),
        headers: await _authHeaders(),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final fileName = item.photo.split('/').last;
        final localPhoto = await LocalImageStorage.saveImage(
          bytes: response.bodyBytes,
          originalName: fileName,
          city: item.city,
          createdAt: item.createdAt,
        );
        return item.copyWith(synced: true, localPhoto: localPhoto);
      }
    } catch (_) {
      // The remote path remains available to CheckInPhoto if downloading
      // locally is unavailable (for example on web or during a LAN outage).
    }
    return item.copyWith(synced: true);
  }

  CheckIn mergeLocalPhotos(CheckIn remote, CheckIn local) {
    final remoteAssets = remote.photoItems;
    final localAssets = local.photoItems;
    final localByRemotePath = {
      for (final asset in localAssets)
        if (asset.photo.isNotEmpty) asset.photo: asset.localPhoto,
    };
    final merged = [
      for (var index = 0; index < remoteAssets.length; index++)
        remoteAssets[index].copyWith(
          localPhoto:
              localByRemotePath[remoteAssets[index].photo] ??
              (index < localAssets.length ? localAssets[index].localPhoto : ''),
        ),
    ];
    final primary = merged.isEmpty ? null : merged.first;
    return remote.copyWith(
      photo: primary?.photo ?? '',
      localPhoto: primary?.localPhoto ?? '',
      photos: merged,
    );
  }

  Uri _photoUri(String photo) {
    final value = photo.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Uri.parse(value);
    }
    final path = value.startsWith('/') ? value : '/$value';
    return Uri.parse('$baseUrl$path');
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

  Future<CheckIn> deletePhotoAsset(String id, String photo) async {
    if (!enabled) throw Exception('Backend sync is disabled.');
    await _ensureBackendAccount();
    final uri = Uri.parse(
      '$baseUrl/api/checkins/$id/photo',
    ).replace(queryParameters: {'photo': photo});
    final response = await http.delete(uri, headers: await _authHeaders());
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return CheckIn.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to delete photo: ${response.statusCode}');
  }
}
