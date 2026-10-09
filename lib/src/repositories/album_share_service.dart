import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:share_plus/share_plus.dart';

import '../models/checkin.dart';
import '../models/travel_album.dart';
import 'image_optimizer.dart';
import 'photo_export.dart';
import 'privacy_settings.dart';

class AlbumShareService {
  const AlbumShareService();

  Future<Uint8List> buildArchive({
    required TravelAlbum album,
    required List<CheckIn> linkedCheckIns,
    required String baseUrl,
  }) async {
    final archive = Archive();
    final privacy = await PrivacySettings.load();
    var index = 0;
    Future<String> addPhoto(String local, String remote, String name) async {
      final bytes = await PhotoExport.readBytes(
        localPhoto: local,
        remotePhoto: remote,
        baseUrl: baseUrl,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError(
          'A photo is unavailable. Sync this album and try sharing again.',
        );
      }
      // Also remove metadata from photos saved by older app versions.
      final clean = await const ImageOptimizer().optimize(bytes, name);
      final file = 'photos/${index++}-${_safeName(clean.fileName, index)}';
      archive.add(ArchiveFile.bytes(file, clean.bytes));
      return file;
    }

    final photos = <Map<String, dynamic>>[];
    for (final photo in album.photos) {
      photos.add({
        'id': photo.id,
        'name': photo.name,
        'place': photo.place,
        'note': photo.note,
        'createdAt': photo.createdAt,
        'file': await addPhoto(photo.localPhoto, photo.photo, photo.name),
      });
    }
    final checkins = <Map<String, dynamic>>[];
    for (final item in linkedCheckIns) {
      final itemPhotos = <Map<String, dynamic>>[];
      for (final photo in item.photoItems) {
        itemPhotos.add({
          'name': photo.name,
          'createdAt': photo.createdAt,
          'file': await addPhoto(photo.localPhoto, photo.photo, photo.name),
        });
      }
      checkins.add({
        'city': item.city,
        'place': item.place,
        'notes': item.notes,
        'createdAt': item.createdAt,
        'album': item.album,
        'favorite': item.favorite,
        'rating': item.rating,
        'tags': item.tags,
        if (!privacy.hideLocation && !item.hideLocation) ...{
          'lat': item.lat,
          'lng': item.lng,
        },
        'photos': itemPhotos,
      });
    }
    archive.add(
      ArchiveFile.string(
        'album.json',
        const JsonEncoder.withIndent('  ').convert({
          'album': {
            'name': album.name,
            'createdAt': album.createdAt,
            'updatedAt': album.updatedAt,
            'coverPhotoId': album.coverPhotoId,
            'photos': photos,
          },
          'checkins': checkins,
        }),
      ),
    );
    return ZipEncoder().encodeBytes(archive);
  }

  Future<void> share({
    required TravelAlbum album,
    required List<CheckIn> linkedCheckIns,
    required String baseUrl,
  }) async {
    final zip = await buildArchive(
      album: album,
      linkedCheckIns: linkedCheckIns,
      baseUrl: baseUrl,
    );
    final fileName =
        '${_safeName(album.name, 0).replaceAll(RegExp(r'\.[^.]+$'), '')}.zip';
    await SharePlus.instance.share(
      ShareParams(
        subject: album.name,
        text: 'VietNam Map Checkin album: ${album.name}',
        files: [XFile.fromData(zip, mimeType: 'application/zip')],
        fileNameOverrides: [fileName],
      ),
    );
  }

  String _safeName(String value, int index) {
    final clean = value
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[^\p{L}\p{N}._-]', unicode: true), '_');
    return clean.isEmpty || clean == '.' || clean == '..'
        ? 'photo-$index'
        : clean;
  }
}
