import 'dart:typed_data';

class LocalImageStorage {
  static bool isLocalRef(String value) => false;

  static Future<String> saveImage({
    required List<int> bytes,
    required String originalName,
    required String city,
    required int createdAt,
  }) async {
    return '';
  }

  static Future<Uint8List?> readImage(String ref) async {
    return null;
  }

  static Future<void> deleteImage(String ref) async {}

  static Future<void> deleteAllImages() async {}

  static Future<String> folderPath() async {
    return 'Local image folder is only available on Android and Windows builds.';
  }
}
