import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checkin.dart';
import '../models/travel_album.dart';
import 'credential_store.dart';
import 'auto_backup_storage.dart';
import 'local_image_storage.dart';

class BackupPayload {
  const BackupPayload({required this.checkIns, required this.albums});

  final List<CheckIn> checkIns;
  final List<TravelAlbum> albums;
}

class BackupService {
  const BackupService();

  static const schema = 'vietnam-map-checkin.backup.v2';
  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2.hmacSha256(iterations: 120000, bits: 256);

  Future<Uint8List> encode({
    required List<CheckIn> checkIns,
    required List<TravelAlbum> albums,
    required String password,
    bool includeImages = true,
  }) async {
    if (password.length < 8) {
      throw const FormatException(
        'Backup password must have at least 8 characters.',
      );
    }
    final images = <String, String>{};
    if (includeImages) {
      final references = <String>{
        for (final item in checkIns)
          for (final photo in item.photoItems)
            if (photo.localPhoto.isNotEmpty) photo.localPhoto,
        for (final album in albums)
          for (final photo in album.photos)
            if (photo.localPhoto.isNotEmpty) photo.localPhoto,
      };
      for (final reference in references) {
        final bytes = await LocalImageStorage.readImage(reference);
        if (bytes != null && bytes.isNotEmpty) {
          images[reference] = base64Encode(bytes);
        }
      }
    }
    final clear = utf8.encode(
      jsonEncode({
        'schema': schema,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'checkins': checkIns.map((item) => item.toJson()).toList(),
        'albums': albums.map((album) => album.toJson()).toList(),
        'images': images,
      }),
    );
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final encrypted = await _cipher.encrypt(
      clear,
      secretKey: key,
      nonce: nonce,
    );
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': schema,
          'encrypted': true,
          'kdf': 'pbkdf2-sha256-120000',
          'cipher': 'aes-256-gcm',
          'salt': base64Encode(salt),
          'nonce': base64Encode(encrypted.nonce),
          'mac': base64Encode(encrypted.mac.bytes),
          'data': base64Encode(encrypted.cipherText),
        }),
      ),
    );
  }

  Future<BackupPayload> decode(Uint8List bytes, String password) async {
    try {
      final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (envelope['schema'] != schema || envelope['encrypted'] != true) {
        throw const FormatException('Unsupported backup format.');
      }
      final key = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: base64Decode(envelope['salt'] as String),
      );
      final clear = await _cipher.decrypt(
        SecretBox(
          base64Decode(envelope['data'] as String),
          nonce: base64Decode(envelope['nonce'] as String),
          mac: Mac(base64Decode(envelope['mac'] as String)),
        ),
        secretKey: key,
      );
      final payload = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      final encodedImages =
          (payload['images'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ) ??
          const <String, String>{};
      final checkIns = <CheckIn>[];
      for (final raw
          in (payload['checkins'] as List? ?? const []).whereType<Map>()) {
        final item = CheckIn.fromJson(Map<String, dynamic>.from(raw));
        final photos = <CheckInPhotoAsset>[];
        for (final photo in item.photoItems) {
          photos.add(
            photo.copyWith(
              localPhoto: await _restoreImage(
                encodedImages,
                photo.localPhoto,
                photo.name,
                item.city,
                item.album,
                photo.createdAt > 0 ? photo.createdAt : item.createdAt,
              ),
            ),
          );
        }
        final primary = photos.isEmpty ? null : photos.first;
        checkIns.add(
          item.copyWith(
            photos: photos,
            photo: primary?.photo ?? item.photo,
            localPhoto: primary?.localPhoto ?? '',
          ),
        );
      }
      final albums = <TravelAlbum>[];
      for (final raw
          in (payload['albums'] as List? ?? const []).whereType<Map>()) {
        final album = TravelAlbum.fromJson(Map<String, dynamic>.from(raw));
        final photos = <AlbumPhoto>[];
        for (final photo in album.photos) {
          photos.add(
            photo.copyWith(
              localPhoto: await _restoreImage(
                encodedImages,
                photo.localPhoto,
                photo.name,
                photo.place.isEmpty ? 'Album' : photo.place,
                album.name,
                photo.createdAt,
              ),
            ),
          );
        }
        albums.add(album.copyWith(photos: photos));
      }
      return BackupPayload(checkIns: checkIns, albums: albums);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Incorrect password or damaged backup.');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Incorrect password or damaged backup.');
    }
  }

  Future<String> _restoreImage(
    Map<String, String> encodedImages,
    String oldReference,
    String name,
    String city,
    String album,
    int createdAt,
  ) async {
    final encoded = encodedImages[oldReference];
    if (encoded == null) return '';
    return LocalImageStorage.saveImage(
      bytes: base64Decode(encoded),
      originalName: name.isEmpty ? 'restored.jpg' : name,
      city: city,
      album: album,
      createdAt: createdAt,
    );
  }

  List<CheckIn> mergeCheckIns(List<CheckIn> current, List<CheckIn> imported) {
    final values = <String, CheckIn>{for (final item in current) item.id: item};
    for (final item in imported) {
      final previous = values[item.id];
      if (previous == null ||
          item.effectiveUpdatedAt >= previous.effectiveUpdatedAt) {
        values[item.id] = item;
      }
    }
    return values.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<TravelAlbum> mergeAlbums(
    List<TravelAlbum> current,
    List<TravelAlbum> imported,
  ) {
    final values = <String, TravelAlbum>{
      for (final item in current) item.id: item,
    };
    for (final item in imported) {
      final previous = values[item.id];
      if (previous == null || item.updatedAt >= previous.updatedAt) {
        values[item.id] = item;
      }
    }
    return values.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
}

class AutoBackupService {
  const AutoBackupService();

  static const intervalKey = 'vmc-auto-backup-days';
  static const _lastKey = 'vmc-auto-backup-last';
  static const _passwordKey = 'vmc-auto-backup-device-password';

  Future<bool> runIfDue(
    List<CheckIn> checkIns,
    List<TravelAlbum> albums, {
    bool force = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final intervalDays = prefs.getInt(intervalKey) ?? 7;
    if (intervalDays <= 0) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = prefs.getInt(_lastKey) ?? 0;
    if (!force && now - last < Duration(days: intervalDays).inMilliseconds) {
      return false;
    }
    var password = await const CredentialStore().readSecret(_passwordKey);
    if (password.isEmpty) {
      final random = Random.secure();
      password = base64UrlEncode(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      await const CredentialStore().writeSecret(_passwordKey, password);
    }
    final bytes = await const BackupService().encode(
      checkIns: checkIns,
      albums: albums,
      password: password,
      includeImages: true,
    );
    await AutoBackupStorage.save(bytes);
    await prefs.setInt(_lastKey, now);
    return true;
  }

  Future<int> lastBackupAt() async =>
      (await SharedPreferences.getInstance()).getInt(_lastKey) ?? 0;
}
