import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

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
    final cityDir = Directory(
      '${root.path}${Platform.pathSeparator}${_safeSegment(city)}',
    );
    await cityDir.create(recursive: true);
    final ext = _extension(originalName);
    final file = File(
      '${cityDir.path}${Platform.pathSeparator}$createdAt-${_safeSegment(_baseName(originalName))}$ext',
    );
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

  static Future<void> deleteAllImages({bool allUsers = false}) async {
    final root = allUsers
        ? await _allUsersRootDirectory()
        : await _rootDirectory();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }

  /// Moves the local image folder when the account username changes.
  static Future<void> moveUserData(String oldName, String newName) async {
    final oldRoot = await _rootDirectory(userName: oldName, create: false);
    if (!await oldRoot.exists()) return;
    final newRoot = await _rootDirectory(userName: newName, create: false);
    if (!await newRoot.exists()) {
      await newRoot.parent.create(recursive: true);
      await oldRoot.rename(newRoot.path);
      return;
    }
    await newRoot.create(recursive: true);
    await for (final entry in oldRoot.list()) {
      final target =
          '${newRoot.path}${Platform.pathSeparator}${entry.uri.pathSegments.last}';
      try {
        await entry.rename(target);
      } catch (_) {
        // Keep the source file if a same-name target already exists.
      }
    }
    var hasRemainingEntries = false;
    if (await oldRoot.exists()) {
      await for (final _ in oldRoot.list()) {
        hasRemainingEntries = true;
        break;
      }
    }
    if (!hasRemainingEntries && await oldRoot.exists()) {
      try {
        await oldRoot.delete(recursive: true);
      } catch (_) {
        // The source folder can be cleaned up on a later account migration.
      }
    }
  }

  static Future<String> folderPath() async {
    return (await _rootDirectory()).path;
  }

  static Future<Directory> _allUsersRootDirectory() async {
    final base = Platform.isAndroid
        ? Directory('/data/user/0/$_androidPackage/files')
        : Directory(
            '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}${Platform.pathSeparator}VietNamMapCheckin',
          );
    return Directory('${base.path}${Platform.pathSeparator}$_folderName');
  }

  static Future<Directory> _rootDirectory({
    String? userName,
    bool create = true,
  }) async {
    final base = Platform.isAndroid
        ? Directory('/data/user/0/$_androidPackage/files')
        : Directory(
            '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}${Platform.pathSeparator}VietNamMapCheckin',
          );
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString('vmc-auth-user')?.trim() ?? '';
    final accountName = userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : storedName;
    final accountFolder = _safeSegment(
      accountName.isEmpty ? 'local' : accountName,
    );
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}$_folderName${Platform.pathSeparator}$accountFolder',
    );
    if (create) await dir.create(recursive: true);
    return dir;
  }

  static String _safeSegment(String value) {
    final cleaned = value.trim().replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
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
