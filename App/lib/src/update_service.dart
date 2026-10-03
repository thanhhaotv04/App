import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class AppVersion {
  const AppVersion({required this.name, required this.code});

  final String name;
  final int code;

  String get label => '$name+$code';
}

class UpdateInfo {
  const UpdateInfo({
    required this.available,
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.notes,
    required this.sha256Digest,
    required this.sizeBytes,
  });

  final bool available;
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String notes;
  final String sha256Digest;
  final int sizeBytes;
}

String normalizeUpdateBaseUrl(String value) {
  var normalized = value.trim();
  if (normalized.isEmpty) {
    throw const FormatException('Enter the update server address.');
  }
  if (!normalized.contains('://')) normalized = 'http://$normalized';
  final uri = Uri.tryParse(normalized);
  if (uri == null ||
      !{'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const FormatException(
      'Invalid update server. Example: http://192.168.1.10:3000',
    );
  }
  return uri.replace(path: '').toString().replaceFirst(RegExp(r'/$'), '');
}

String friendlyUpdateError(Object error) {
  if (error is PlatformException) {
    return error.message?.trim().isNotEmpty == true
        ? error.message!
        : 'Could not open the APK installer.';
  }
  if (error is FormatException) return error.message;
  if (error is TimeoutException) {
    return 'The update server timed out. Please try again.';
  }
  return 'Could not check for updates. Check the server address and network connection.';
}

class AppUpdateService {
  AppUpdateService({required String baseUrl, this._client})
    : baseUrl = normalizeUpdateBaseUrl(baseUrl);

  static const fallbackVersion = AppVersion(name: '261001.3', code: 26100103);
  static const maxApkBytes = 200 * 1024 * 1024;
  static const _channel = MethodChannel('esp32_navride/update');

  final String baseUrl;
  final http.Client? _client;

  Future<T> _withClient<T>(
    Future<T> Function(http.Client client) action,
  ) async {
    if (_client != null) return action(_client);
    final client = http.Client();
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  Future<AppVersion> currentVersion() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return fallbackVersion;
    }
    final data = await _channel.invokeMapMethod<String, dynamic>(
      'getAppVersion',
    );
    final name = data?['versionName'];
    final code = data?['versionCode'];
    if (name is! String || name.isEmpty || code is! int || code <= 0) {
      throw const FormatException('Could not read the installed app version.');
    }
    return AppVersion(name: name, code: code);
  }

  Future<UpdateInfo> checkLatest({required int currentVersionCode}) async {
    final base = Uri.parse(baseUrl);
    final uri = base.resolve('/api/update/latest');
    final data = await _withClient((client) async {
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException(
          'The update server returned HTTP ${response.statusCode}.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        if (bytes.length + chunk.length > 64 * 1024) {
          throw const FormatException('Update metadata is too large.');
        }
        bytes.addAll(chunk);
      }
      try {
        return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } catch (_) {
        throw const FormatException(
          'The server returned invalid update metadata.',
        );
      }
    });

    final apkValue = data['apkUrl'];
    final versionName = data['versionName'];
    final notes = data['notes'];
    final size = data['sizeBytes'];
    final code = data['versionCode'];
    final digest = data['sha256'];
    if (apkValue is! String) {
      throw const FormatException('Update metadata is missing the APK URL.');
    }
    final apk = base.resolve(apkValue);
    if (apk.origin != base.origin ||
        !apk.path.startsWith('/releases/') ||
        !apk.path.toLowerCase().endsWith('.apk') ||
        apk.hasQuery ||
        apk.hasFragment ||
        apk.userInfo.isNotEmpty ||
        versionName is! String ||
        versionName.trim().isEmpty ||
        versionName.length > 50 ||
        notes is! String ||
        notes.length > 4000 ||
        size is! int ||
        size <= 0 ||
        size > maxApkBytes ||
        code is! int ||
        code <= 0 ||
        code > 2100000000 ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException(
        'Could not verify update metadata. Check the server.',
      );
    }
    return UpdateInfo(
      available: code > currentVersionCode,
      versionName: versionName,
      versionCode: code,
      apkUrl: apk.toString(),
      notes: notes,
      sha256Digest: digest,
      sizeBytes: size,
    );
  }

  Future<String> downloadApk(
    UpdateInfo info, {
    void Function(double progress)? onProgress,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const FormatException(
        'APK installation is available on Android only.',
      );
    }
    final base = Uri.parse(baseUrl);
    final uri = Uri.parse(info.apkUrl);
    if (uri.origin != base.origin ||
        !uri.path.startsWith('/releases/') ||
        info.sizeBytes <= 0 ||
        info.sizeBytes > maxApkBytes) {
      throw const FormatException('The update download source is not trusted.');
    }
    final cachePath = await _channel.invokeMethod<String>('getCacheDirectory');
    if (cachePath == null || cachePath.isEmpty) {
      throw const FormatException(
        'Could not access Android temporary storage.',
      );
    }
    final directory = await Directory(
      '$cachePath/esp32-navride-updates',
    ).create(recursive: true);
    final partial = File(
      '${directory.path}/update-${info.versionCode}.apk.part',
    );
    IOSink? sink;
    try {
      await _withClient((client) async {
        final response = await client
            .send(http.Request('GET', uri)..followRedirects = false)
            .timeout(const Duration(seconds: 15));
        if (response.statusCode != 200 ||
            (response.contentLength != null &&
                response.contentLength != info.sizeBytes)) {
          throw const FormatException(
            'The update file has an unexpected size or could not be downloaded.',
          );
        }
        sink = partial.openWrite();
        final timer = Stopwatch()..start();
        var received = 0;
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 15),
        )) {
          received += chunk.length;
          if (received > info.sizeBytes ||
              timer.elapsed > const Duration(minutes: 3)) {
            throw const FormatException(
              'The update download exceeded the size limit.',
            );
          }
          sink!.add(chunk);
          onProgress?.call((received / info.sizeBytes).clamp(0, 1));
        }
        await sink!.flush();
        await sink!.close();
        sink = null;
        if (received != info.sizeBytes ||
            (await sha256.bind(partial.openRead()).first).toString() !=
                info.sha256Digest) {
          throw const FormatException(
            'The downloaded APK is incomplete or failed SHA-256 verification.',
          );
        }
      });
      final signature = await partial.openRead(0, 4).expand((v) => v).toList();
      if (!listEquals(signature, const [0x50, 0x4b, 0x03, 0x04])) {
        throw const FormatException('The downloaded file is not a valid APK.');
      }
      final target = File('${directory.path}/update-${info.versionCode}.apk');
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      return target.path;
    } finally {
      await sink?.close();
      if (await partial.exists()) await partial.delete();
    }
  }

  Future<void> installApk(String path) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const FormatException(
        'APK installation is available on Android only.',
      );
    }
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }
}
