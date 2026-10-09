import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/checkin.dart';
import '../models/sync_state.dart';
import 'auth_service.dart';
import 'credential_store.dart';
import 'local_image_storage.dart';
import 'image_optimizer.dart';
import 'private_photo.dart';
import 'sync_queue_repository.dart';

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
    this.token,
    this.client,
  });

  final String baseUrl;
  final String? userName;
  final String? password;
  final String? token;
  final http.Client? client;

  bool get enabled => baseUrl.isNotEmpty;

  Future<Map<String, String>> _authHeaders() async {
    return const CredentialStore().authHeaders(
      userName: userName,
      migrationPassword: password,
      token: token,
      baseUrl: baseUrl,
    );
  }

  Future<void> _ensureBackendAccount() async {
    try {
      await _authHeaders();
      return;
    } catch (_) {
      // Explicit credentials below can obtain a token for older callers.
    }
    final name = userName?.trim() ?? '';
    final pass = password ?? '';
    if (name.isEmpty || pass.isEmpty) {
      throw StateError('Sign in again before syncing with the backend.');
    }
    final session = await AuthService(
      baseUrl: baseUrl,
      client: client,
    ).loginSession(name, pass);
    await const CredentialStore().saveSession(
      userName: session.name,
      password: pass,
      token: session.token,
      baseUrl: baseUrl,
    );
  }

  Future<List<CheckIn>> fetchRemote() async {
    if (!enabled) return [];
    await _ensureBackendAccount();
    final headers = await _authHeaders();
    final res =
        await (client?.get(
                  Uri.parse('$baseUrl/api/checkins'),
                  headers: headers,
                ) ??
                http.get(Uri.parse('$baseUrl/api/checkins'), headers: headers))
            .timeout(const Duration(seconds: 10));
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
    bool force = false,
  }) async {
    if (!enabled) return item;
    await _ensureBackendAccount();
    final pendingAssets = item.photoItems
        .where((entry) => entry.photo.isEmpty && entry.localPhoto.isNotEmpty)
        .toList();
    final changesPhotos =
        (photoUploads?.isNotEmpty ?? false) ||
        (photoBytes?.isNotEmpty ?? false) ||
        pendingAssets.isNotEmpty;
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
            'updatedAt': item.effectiveUpdatedAt.toString(),
            'baseUpdatedAt': item.syncedAt.toString(),
            'lat': (item.hideLocation ? 0 : item.lat).toString(),
            'lng': (item.hideLocation ? 0 : item.lng).toString(),
            'favorite': item.favorite.toString(),
            'rating': item.rating.toString(),
            'tags': jsonEncode(item.tags),
            'album': item.album,
            'hideLocation': item.hideLocation.toString(),
            if (force) 'force': 'true',
            if (changesPhotos)
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
        final clean = await const ImageOptimizer().optimize(
          upload.bytes,
          upload.fileName,
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            clean.bytes,
            filename: clean.fileName,
          ),
        );
      }
    } else {
      if (photoBytes != null && photoBytes.isNotEmpty) {
        final clean = await const ImageOptimizer().optimize(
          photoBytes,
          photoFileName ?? 'checkin-photo.jpg',
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            clean.bytes,
            filename: clean.fileName,
          ),
        );
      }
      final assetsToRead = photoBytes != null && photoBytes.isNotEmpty
          ? pendingAssets.skip(1)
          : pendingAssets;
      for (final asset in assetsToRead) {
        final bytes = await LocalImageStorage.readImage(asset.localPhoto);
        if (bytes == null || bytes.isEmpty) continue;
        final clean = await const ImageOptimizer().optimize(
          bytes,
          asset.name.isEmpty ? 'checkin-photo.jpg' : asset.name,
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            clean.bytes,
            filename: clean.fileName,
          ),
        );
      }
    }
    final streamed = await (client?.send(request) ?? request.send());
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return CheckIn.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    if (res.statusCode == 409) {
      final data = jsonDecode(res.body);
      if (data is Map && data['remote'] is Map) {
        throw CheckInConflictException(
          CheckIn.fromJson(Map<String, dynamic>.from(data['remote'] as Map)),
        );
      }
    }
    throw Exception('Failed to push checkin: ${res.statusCode} ${res.body}');
  }

  Future<List<CheckIn>> syncTwoWay(List<CheckIn> localItems) async {
    if (!enabled) return localItems;
    final queue = SyncQueueRepository(userName: userName);
    final operations = await queue.loadOperations();
    final pendingDeleteIds = operations
        .where((operation) => operation.type == SyncOperationType.deleteCheckIn)
        .map((operation) => operation.checkInId)
        .toSet();
    for (final operation in operations.where(
      (value) => value.type == SyncOperationType.deleteCheckIn,
    )) {
      try {
        await deleteCheckIn(operation.checkInId);
        await queue.complete(operation.id);
        pendingDeleteIds.remove(operation.checkInId);
      } catch (error) {
        await queue.fail(operation.id, error);
      }
    }
    final remoteBefore = await fetchRemote();
    final remoteById = {for (final item in remoteBefore) item.id: item};
    final localById = {for (final item in localItems) item.id: item};
    final pushed = <String, CheckIn>{};
    for (final item in localItems) {
      if (item.localOnly || pendingDeleteIds.contains(item.id)) continue;
      final remote = remoteById[item.id];
      final shouldPush =
          remote == null ||
          !item.synced ||
          (item.localPhoto.isNotEmpty && (remote.photo.isEmpty));
      if (shouldPush) {
        try {
          final uploaded = await push(item);
          pushed[item.id] = mergeLocalPhotos(
            uploaded.copyWith(
              synced: true,
              syncedAt: uploaded.effectiveUpdatedAt,
            ),
            item,
          );
          await queue.completeForCheckIn(item.id);
          await queue.removeConflict(item.id);
        } on CheckInConflictException catch (error) {
          await queue.saveConflict(item, error.remote);
        } catch (error) {
          final operation = operations
              .where((value) => value.checkInId == item.id)
              .firstOrNull;
          if (operation != null) await queue.fail(operation.id, error);
        }
      }
    }
    final remoteAfter = await fetchRemote();
    final byId = <String, CheckIn>{};
    for (final remote in remoteAfter) {
      if (pendingDeleteIds.contains(remote.id)) continue;
      final local = localById[remote.id];
      final conflicts = await queue.loadConflicts();
      if (conflicts.any((conflict) => conflict.checkInId == remote.id)) {
        if (local != null) byId[remote.id] = local;
        continue;
      }
      if (local != null && local.photoItems.isNotEmpty) {
        byId[remote.id] = mergeLocalPhotos(
          remote.copyWith(synced: true, syncedAt: remote.effectiveUpdatedAt),
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
      if (local.localOnly || pendingDeleteIds.contains(local.id)) {
        byId[local.id] = local;
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
      byId[local.id] = mergeLocalPhotos(
        remote.copyWith(synced: true, syncedAt: remote.effectiveUpdatedAt),
        local,
      );
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
      final bytes = await PrivatePhoto.read(
        baseUrl: baseUrl,
        photo: item.photo,
        headers: await _authHeaders(),
        client: client,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final fileName = item.photo.split('/').last;
        final localPhoto = await LocalImageStorage.saveImage(
          bytes: bytes,
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
      lat: local.hideLocation ? local.lat : remote.lat,
      lng: local.hideLocation ? local.lng : remote.lng,
      hideLocation: local.hideLocation,
    );
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

  Future<CheckIn> forcePush(CheckIn item) => push(item, force: true);

  Future<({int usedBytes, int limitBytes})> storageUsage() async {
    final response =
        await (client?.get(
                  Uri.parse('$baseUrl/api/account/storage'),
                  headers: await _authHeaders(),
                ) ??
                http.get(
                  Uri.parse('$baseUrl/api/account/storage'),
                  headers: await _authHeaders(),
                ))
            .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Could not load storage usage.');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (
      usedBytes: (data['usedBytes'] as num?)?.toInt() ?? 0,
      limitBytes: (data['limitBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> deleteAccount(String confirmation) async {
    final request = http.Request('DELETE', Uri.parse('$baseUrl/api/account'))
      ..headers.addAll({
        ...await _authHeaders(),
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({'confirmation': confirmation});
    final streamed = await (client?.send(request) ?? request.send());
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Account deletion failed (${response.statusCode}).');
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

class CheckInConflictException implements Exception {
  const CheckInConflictException(this.remote);

  final CheckIn remote;
}
