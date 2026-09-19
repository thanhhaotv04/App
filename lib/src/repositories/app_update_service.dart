import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

import '../app_version.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.available,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.notes,
    required this.sha256,
  });

  final bool available;
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String notes;
  final String sha256;
}

class AppUpdateService {
  const AppUpdateService({required this.baseUrl});

  static const _channel = MethodChannel('vietnam_map_checkin/update');

  final String baseUrl;

  Future<UpdateInfo> checkLatest() async {
    final res = await http
        .get(Uri.parse('$baseUrl/api/update/latest'))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Update check failed: ${res.statusCode}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final remoteCode = (json['versionCode'] as num?)?.toInt() ?? 0;
    final apkPath = json['apkUrl']?.toString() ?? '';
    final apkUrl = apkPath.startsWith('http') ? apkPath : '$baseUrl$apkPath';
    return UpdateInfo(
      available: remoteCode > AppVersion.versionCode,
      versionName: json['versionName']?.toString() ?? '',
      versionCode: remoteCode,
      apkUrl: apkUrl,
      notes: json['notes']?.toString() ?? '',
      sha256: json['sha256']?.toString().toLowerCase() ?? '',
    );
  }

  Future<String> downloadApk(UpdateInfo info) async {
    final res = await http
        .get(Uri.parse(info.apkUrl))
        .timeout(const Duration(minutes: 2));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('APK download failed: ${res.statusCode}');
    }
    final digest = sha256.convert(res.bodyBytes).toString();
    if (info.sha256.length != 64 || digest != info.sha256) {
      throw Exception('APK integrity check failed. The download was rejected.');
    }
    final dir = await _downloadDir();
    final file = File(
      '${dir.path}${Platform.pathSeparator}vietnam-map-checkin-${info.versionCode}.apk',
    );
    await file.writeAsBytes(res.bodyBytes, flush: true);
    return file.path;
  }

  Future<void> installApk(String apkPath) async {
    if (!Platform.isAndroid) {
      throw Exception('APK install is only available on Android.');
    }
    final file = File(apkPath);
    final downloadRoot = (await _downloadDir()).absolute.path;
    final absolutePath = file.absolute.path;
    if (!absolutePath.startsWith('$downloadRoot${Platform.pathSeparator}') ||
        !await file.exists()) {
      throw Exception('Update file is outside the app cache.');
    }
    await _channel.invokeMethod<void>('installApk', {'path': absolutePath});
  }

  Future<Directory> _downloadDir() async {
    final base = Platform.isAndroid
        ? Directory('/data/user/0/com.example.vietnam_map_01/cache')
        : Directory(
            '${Platform.environment['LOCALAPPDATA'] ?? Directory.current.path}${Platform.pathSeparator}VietNamMapCheckin',
          );
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    await dir.create(recursive: true);
    return dir;
  }
}
