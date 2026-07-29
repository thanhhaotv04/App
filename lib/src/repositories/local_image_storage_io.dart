import 'dart:io';
import 'dart:typed_data';

class LocalImageStorage {
  static const _androidPackage = 'com.example.vietnam_map_01';
  static const _folderName = 'vietnam_map_checkin_images';
  static const _prefix = 'local:';

  static bool isLocalRef(String value) => value.startsWith(_prefix);

  static Future<String> saveImage({
    required List<int> bytes,
    required String originalName,
    required String city,
    required int createdAt,
  }) async {
    if (bytes.isEmpty) return '';
    final root = await _rootDirectory();
    final cityDir = Directory('${root.path}${Platform.pathSeparator}${_safeSegment(city)}');
    await cityDir.create(recursive: true);
    final ext = _extension(originalName);
    final file = File('${cityDir.path}${Platform.pathSeparator}$createdAt-${_safeSegment(_baseName(originalName))}$ext');
    await file.writeAsBytes(bytes, flush: true);
    return '$_prefix${file.path}';
  }

  static Future<Uint8List?> readImage(String ref) async {
    if (!isLocalRef(ref)) return null;
    final file = File(ref.substring(_prefix.length));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  static Future<void> deleteImage(String ref) async {
    if (!isLocalRef(ref)) return;
    final file = File(ref.substring(_prefix.length));
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<void> deleteAllImages() async {
    final root = await _rootDirectory();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  static Future<String> folderPath() async {
    return (await _rootDirectory()).path;
  }

  static Future<Directory> _rootDirectory() async {
    final base = Platform.isAndroid
        ? Directory('/data/user/0/$_androidPackage/files')
        : Directory('${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}${Platform.pathSeparator}VietNamMapCheckin');
    final dir = Directory('${base.path}${Platform.pathSeparator}$_folderName');
    await dir.create(recursive: true);
    return dir;
  }

  static String _safeSegment(String value) {
    final cleaned = value.trim().replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return cleaned.isEmpty ? 'Unknown' : cleaned;
  }

  static String _baseName(String value) {
    final normalized = value.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  static String _extension(String value) {
    final name = value.replaceAll('\\', '/').split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '.jpg';
    final ext = name.substring(dot).toLowerCase();
    return ext.length > 8 ? '.jpg' : ext;
  }
}
