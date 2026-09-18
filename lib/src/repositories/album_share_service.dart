import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:share_plus/share_plus.dart';

import '../models/checkin.dart';
import '../models/travel_album.dart';
import 'photo_export.dart';

class AlbumShareService {
  const AlbumShareService();

  Future<void> share({
    required TravelAlbum album,
    required List<CheckIn> linkedCheckIns,
    required String baseUrl,
  }) async {
    final archive = Archive();
    archive.add(
      ArchiveFile.string(
        'album.json',
        const JsonEncoder.withIndent('  ').convert({
          'album': album.toJson(),
          'checkins': linkedCheckIns
              .map(
                (item) => item
                    .copyWith(
                      lat: item.hideLocation ? 0 : item.lat,
                      lng: item.hideLocation ? 0 : item.lng,
                    )
                    .toJson(),
              )
              .toList(),
        }),
      ),
    );
    var index = 0;
    for (final photo in album.photos) {
      final bytes = await PhotoExport.readBytes(
        localPhoto: photo.localPhoto,
        remotePhoto: photo.photo,
        baseUrl: baseUrl,
      );
      if (bytes == null || bytes.isEmpty) continue;
      final name = _safeName(photo.name, index++);
      archive.add(ArchiveFile.bytes('photos/$name', bytes));
    }
    for (final item in linkedCheckIns) {
      for (final photo in item.photoItems) {
        final bytes = await PhotoExport.readBytes(
          localPhoto: photo.localPhoto,
          remotePhoto: photo.photo,
          baseUrl: baseUrl,
        );
        if (bytes == null || bytes.isEmpty) continue;
        archive.add(
          ArchiveFile.bytes('photos/${_safeName(photo.name, index++)}', bytes),
        );
      }
    }
    final zip = ZipEncoder().encodeBytes(archive);
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
    if (clean.isEmpty || !clean.contains('.')) return 'photo-$index.jpg';
    return clean;
  }
}
