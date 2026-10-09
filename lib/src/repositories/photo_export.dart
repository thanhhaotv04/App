import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_image_storage.dart';
import 'credential_store.dart';
import 'private_photo.dart';

/// Exports a private app photo to a location chosen by the user.
class PhotoExport {
  static const _androidChannel = MethodChannel('vietnam_map_checkin/photos');

  static Future<bool> save({
    required String localPhoto,
    required String remotePhoto,
    required String baseUrl,
    required String fileName,
  }) async {
    final bytes = await readBytes(
      localPhoto: localPhoto,
      remotePhoto: remotePhoto,
      baseUrl: baseUrl,
    );
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Photo is unavailable on this device and backend.');
    }

    final safeName = _safeFileName(fileName);
    final mimeType = switch (safeName.split('.').last.toLowerCase()) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => 'image/jpeg',
    };
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return await _androidChannel.invokeMethod<bool>('saveImage', {
            'bytes': bytes,
            'name': safeName,
            'mimeType': mimeType,
          }) ??
          false;
    }
    final location = await getSaveLocation(suggestedName: safeName);
    if (location == null) return false;
    await XFile.fromData(
      bytes,
      name: safeName,
      mimeType: mimeType,
    ).saveTo(location.path);
    return true;
  }

  static Future<Uint8List?> readBytes({
    required String localPhoto,
    required String remotePhoto,
    required String baseUrl,
  }) async {
    Uint8List? bytes = await LocalImageStorage.readImage(localPhoto);
    if ((bytes == null || bytes.isEmpty) && remotePhoto.isNotEmpty) {
      bytes = await PrivatePhoto.read(
        baseUrl: baseUrl,
        photo: remotePhoto,
        headers: await const CredentialStore().authHeaders(baseUrl: baseUrl),
      );
    }
    return bytes;
  }

  static String _safeFileName(String value) {
    final clean = value
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[^\p{L}\p{N}._-]', unicode: true), '_');
    if (clean.isEmpty || clean == '.' || clean == '..') return 'memory.jpg';
    return clean.contains('.') ? clean : '$clean.jpg';
  }
}
