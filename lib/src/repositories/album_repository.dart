import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/travel_album.dart';
import 'backend_config.dart';
import 'private_photo.dart';
import 'image_optimizer.dart';
import 'credential_store.dart';
import 'local_image_storage.dart';

/// Album records are separate from check-ins and stored under the signed-in user.
class AlbumRepository {
  AlbumRepository({this.userName});

  static const _storagePrefix = 'vnm_albums_user_';
  static const _userKey = 'vmc-auth-user';

  final String? userName;

  Future<List<TravelAlbum>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyFor(await _currentName(prefs)));
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded
        .whereType<Map>()
        .map((value) => TravelAlbum.fromJson(Map<String, dynamic>.from(value)))
        .where((album) => album.id.isNotEmpty && album.name.isNotEmpty)
        .toList();
  }

  Future<void> save(List<TravelAlbum> albums) async {
    final prefs = await SharedPreferences.getInstance();
    final name = await _currentName(prefs);
    await prefs.setString(
      _keyFor(name),
      jsonEncode(albums.map((album) => album.toJson()).toList()),
    );
  }

  Future<void> upsert(TravelAlbum album) async {
    final albums = await load();
    final index = albums.indexWhere((item) => item.id == album.id);
    if (index < 0) {
      albums.add(album);
    } else {
      albums[index] = album;
    }
    await save(albums);
  }

  /// Pulls remote albums, uploads local-only photos, then saves the merged set.
  /// A failed network request leaves all local albums and photos untouched.
  Future<List<TravelAlbum>> syncTwoWay({String? baseUrl}) async {
    final prefs = await SharedPreferences.getInstance();
    final name = await _currentName(prefs);
    final url = (baseUrl ?? await BackendConfig.loadUrl()).replaceAll(
      RegExp(r'/+$'),
      '',
    );
    final headers = await const CredentialStore().authHeaders(
      userName: name,
      baseUrl: url,
    );
    final remoteResponse = await http
        .get(Uri.parse('$url/api/albums'), headers: headers)
        .timeout(const Duration(seconds: 12));
    _requireSuccess(remoteResponse);
    final remote = (jsonDecode(remoteResponse.body) as List)
        .whereType<Map>()
        .map((value) => TravelAlbum.fromJson(Map<String, dynamic>.from(value)))
        .toList();
    final merged = <String, TravelAlbum>{
      for (final album in remote) album.id: album,
    };
    for (final local in await load()) {
      final previous = merged[local.id];
      merged[local.id] = previous == null ? local : _merge(previous, local);
    }

    final result = <TravelAlbum>[];
    for (var album in merged.values) {
      if (album.localOnly) {
        result.add(album);
        continue;
      }
      final response = await http
          .post(
            Uri.parse('$url/api/albums'),
            headers: {...headers, 'Content-Type': 'application/json'},
            body: jsonEncode(album.toJson()),
          )
          .timeout(const Duration(seconds: 12));
      _requireSuccess(response);
      album = _merge(album, TravelAlbum.fromJson(jsonDecode(response.body)));
      if (album.isDeleted) {
        result.add(album);
        continue;
      }
      final photos = <AlbumPhoto>[];
      for (final photo in album.photos) {
        var current = photo;
        if (photo.photo.isEmpty && photo.localPhoto.isNotEmpty) {
          final bytes = await LocalImageStorage.readImage(photo.localPhoto);
          if (bytes != null && bytes.isNotEmpty) {
            final clean = await const ImageOptimizer().optimize(
              bytes,
              photo.name.isEmpty ? 'album-photo.jpg' : photo.name,
            );
            final upload = http.MultipartRequest(
              'POST',
              Uri.parse(
                '$url/api/albums/${Uri.encodeComponent(album.id)}/photos',
              ),
            )..headers.addAll(headers);
            upload.fields['photoId'] = photo.id;
            upload.fields['createdAt'] = photo.createdAt.toString();
            upload.fields['place'] = photo.place;
            upload.fields['note'] = photo.note;
            upload.files.add(
              http.MultipartFile.fromBytes(
                'photo',
                clean.bytes,
                filename: clean.fileName,
              ),
            );
            final streamed = await upload.send().timeout(
              const Duration(seconds: 30),
            );
            final uploaded = await http.Response.fromStream(streamed);
            _requireSuccess(uploaded);
            final asset = AlbumPhoto.fromJson(jsonDecode(uploaded.body));
            current = photo.copyWith(photo: asset.photo);
          }
        }
        if (current.photo.isNotEmpty && current.localPhoto.isEmpty) {
          try {
            final downloaded = await PrivatePhoto.read(
              baseUrl: url,
              photo: current.photo,
              headers: headers,
            );
            if (downloaded != null && downloaded.isNotEmpty) {
              final localRef = await LocalImageStorage.saveImage(
                bytes: downloaded,
                originalName: current.name.isEmpty
                    ? 'album-photo.jpg'
                    : current.name,
                city: 'Album',
                album: album.name,
                createdAt: current.createdAt,
              );
              current = current.copyWith(localPhoto: localRef);
            }
          } catch (_) {
            // A backend photo remains available online; retry the offline copy later.
          }
        }
        photos.add(current);
      }
      result.add(album.copyWith(photos: photos));
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await save(result);
    return result;
  }

  static TravelAlbum _merge(TravelAlbum a, TravelAlbum b) {
    final newest = a.updatedAt >= b.updatedAt ? a : b;
    if (a.isDeleted || b.isDeleted) {
      return (a.isDeleted ? a : b).copyWith(
        updatedAt: newest.updatedAt,
        checkInIds: [],
        photos: [],
        isDeleted: true,
      );
    }
    final deletedPhotoIds = {...a.deletedPhotoIds, ...b.deletedPhotoIds};
    final excludedCheckInIds = newest.excludedCheckInIds.toSet();
    final photos = <String, AlbumPhoto>{
      for (final photo in a.photos)
        if (!deletedPhotoIds.contains(photo.id)) photo.id: photo,
    };
    for (final photo in b.photos) {
      if (deletedPhotoIds.contains(photo.id)) continue;
      final old = photos[photo.id];
      photos[photo.id] = old == null
          ? photo
          : photo.copyWith(
              photo: photo.photo.isNotEmpty ? photo.photo : old.photo,
              localPhoto: photo.localPhoto.isNotEmpty
                  ? photo.localPhoto
                  : old.localPhoto,
              place: photo.place.isNotEmpty ? photo.place : old.place,
              note: photo.note.isNotEmpty ? photo.note : old.note,
            );
    }
    return newest.copyWith(
      checkInIds: {
        ...a.checkInIds,
        ...b.checkInIds,
      }.where((id) => !excludedCheckInIds.contains(id)).toList(),
      photos: photos.values.toList(),
      deletedPhotoIds: deletedPhotoIds.toList(),
      excludedCheckInIds: excludedCheckInIds.toList(),
    );
  }

  static void _requireSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Album sync failed (${response.statusCode}).');
    }
  }

  Future<String> _currentName(SharedPreferences prefs) async {
    final name = userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : prefs.getString(_userKey)?.trim() ?? '';
    if (name.isEmpty) throw StateError('Sign in before opening albums.');
    return name;
  }

  static String _keyFor(String name) =>
      '$_storagePrefix${base64UrlEncode(utf8.encode(name.trim().toLowerCase()))}';

  static Future<void> moveUserData(String oldName, String newName) async {
    final prefs = await SharedPreferences.getInstance();
    final oldKey = _keyFor(oldName);
    final newKey = _keyFor(newName);
    if (oldKey == newKey) return;
    final oldRaw = prefs.getString(oldKey);
    if (oldRaw == null) return;
    final oldAlbums = (jsonDecode(oldRaw) as List).whereType<Map>().map(
      (value) => TravelAlbum.fromJson(Map<String, dynamic>.from(value)),
    );
    final migrated = <TravelAlbum>[];
    for (final album in oldAlbums) {
      final photos = <AlbumPhoto>[];
      for (final photo in album.photos) {
        photos.add(
          photo.copyWith(
            localPhoto: await LocalImageStorage.movedRef(
              photo.localPhoto,
              oldName,
              newName,
            ),
          ),
        );
      }
      migrated.add(album.copyWith(photos: photos));
    }
    final existingRaw = prefs.getString(newKey);
    final combined = <String, TravelAlbum>{};
    if (existingRaw != null) {
      for (final value in (jsonDecode(existingRaw) as List).whereType<Map>()) {
        final album = TravelAlbum.fromJson(Map<String, dynamic>.from(value));
        combined[album.id] = album;
      }
    }
    for (final album in migrated) {
      final previous = combined[album.id];
      combined[album.id] = previous == null ? album : _merge(previous, album);
    }
    final encoded = jsonEncode(
      combined.values.map((album) => album.toJson()).toList(),
    );
    await prefs.setString(newKey, encoded);
    if (prefs.getString(newKey) == encoded) await prefs.remove(oldKey);
  }

  static Future<void> clearCurrentData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_userKey)?.trim() ?? '';
    if (name.isNotEmpty) await prefs.remove(_keyFor(name));
  }
}
