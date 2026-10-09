import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'storage.dart';

class AuthException implements Exception {
  const AuthException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

String friendlyError(Object error) {
  if (error is PlatformException && error.code == 'install_failed') {
    return error.message?.trim().isNotEmpty == true
        ? error.message!
        : 'The update could not be installed. Check installation permissions and try again.';
  }
  if (error is AuthException) return error.message;
  if (error is FormatException) return error.message;
  if (error is TimeoutException) {
    return 'The server took too long to respond. Your local data is safe. Try again.';
  }
  return 'Could not connect securely. Check your connection, server address and certificate, then try again.';
}

Uri serverUri(String baseUrl, String path) {
  final base = BackendConfig.normalize(baseUrl);
  final uri = Uri.parse('$base$path');
  if (kReleaseMode && uri.scheme != 'https') {
    throw const FormatException('Use HTTPS to connect securely.');
  }
  return uri;
}

Future<Map<String, dynamic>> apiRequest(
  String baseUrl,
  String path, {
  Map<String, Object?>? body,
  String? token,
}) async {
  final uri = serverUri(baseUrl, path);
  final client = http.Client();
  try {
    return await (() async {
      final request = http.Request(body == null ? 'GET' : 'POST', uri)
        ..followRedirects = false;
      request.headers['Accept'] = 'application/json';
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        request.body = jsonEncode(body);
      }
      final response = await client.send(request);
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 5 * 1024 * 1024) {
          throw const FormatException(
            'Server response is too large. Your local data was preserved.',
          );
        }
        bytes.addAll(chunk);
      }
      Map<String, dynamic> data;
      try {
        data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      } catch (_) {
        throw const FormatException(
          'The server returned an unexpected response. Check the server address and try again.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthException(
          data['message'] is String
              ? data['message'] as String
              : 'Request failed. Please try again.',
          status: response.statusCode,
        );
      }
      return data;
    })().timeout(const Duration(seconds: 15));
  } finally {
    client.close();
  }
}

class AuthService {
  const AuthService({required this.baseUrl});
  final String baseUrl;
  AuthSession _session(Map<String, dynamic> data) {
    if (data['name'] is! String ||
        data['id'] is! String ||
        data['token'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['token'] as String)) {
      throw const FormatException(
        'Update the server to enable secure sign-in.',
      );
    }
    return AuthSession(
      name: data['name'] as String,
      id: data['id'] as String,
      token: data['token'] as String,
      backendUrl: BackendConfig.normalize(baseUrl),
    );
  }

  Future<AuthSession> signIn(String name, String password) async => _session(
    await apiRequest(
      baseUrl,
      '/api/auth/login',
      body: {'name': name, 'password': password},
    ),
  );
  Future<AuthSession> register(String name, String password) async => _session(
    await apiRequest(
      baseUrl,
      '/api/auth/register',
      body: {'name': name, 'password': password},
    ),
  );
  Future<void> resetPassword(
    String name,
    String newPassword,
    String recoveryCode,
  ) async {
    await apiRequest(
      baseUrl,
      '/api/auth/reset-password',
      body: {
        'name': name,
        'newPassword': newPassword,
        'recoveryCode': recoveryCode,
      },
    );
  }

  Future<AuthSession> updatePassword({
    required AuthSession session,
    required String currentPassword,
    required String newPassword,
  }) async {
    final signed = await ensureSession(session);
    return _session(
      await apiRequest(
        baseUrl,
        '/api/auth/update',
        token: signed.token,
        body: {'currentPassword': currentPassword, 'newPassword': newPassword},
      ),
    );
  }

  Future<void> signOut(AuthSession session) async {
    if (session.token != null) {
      await apiRequest(
        session.backendUrl,
        '/api/auth/logout',
        token: session.token,
        body: {},
      );
    }
  }

  static Future<AuthSession> ensureSession(AuthSession session) async {
    if (session.id.isNotEmpty && session.token != null) return session;
    throw const AuthException(
      'Sign in again to sync. Older data is available through recovery.',
    );
  }

  static Future<int> retryPendingLogouts() async {
    for (final session in await AuthCache.pendingLogouts()) {
      try {
        await AuthService(baseUrl: session.backendUrl).signOut(session);
        await AuthCache.finishLogout(session);
      } catch (_) {
        // Keep the encrypted token queued until the server confirms revocation.
      }
    }
    return (await AuthCache.pendingLogouts()).length;
  }
}

class MoneySyncService {
  const MoneySyncService({required this.session});
  final AuthSession session;
  Future<MoneySyncData> syncTwoWay(MoneySyncData local) async {
    final signed = await AuthService.ensureSession(session);
    for (final batch in _batches(local)) {
      final ack = await apiRequest(
        signed.backendUrl,
        '/api/money-manager/data',
        token: signed.token,
        body: {'protocol': 3, ...batch},
      );
      if (ack['protocol'] != 3) {
        throw const FormatException(
          'Update the server before syncing. Local data was preserved.',
        );
      }
    }
    // A concurrent writer may change the snapshot between pages. Restart the
    // read, never combine pages from different server revisions.
    for (var attempt = 0; attempt < 3; attempt++) {
      final result = <String, dynamic>{
        for (final key in _keys) key: <dynamic>[],
      };
      String? revision;
      int? cursor = 0;
      try {
        do {
          final data = await apiRequest(
            signed.backendUrl,
            '/api/money-manager/data?cursor=$cursor${revision == null ? '' : '&revision=$revision'}',
            token: signed.token,
          );
          if (data['protocol'] != 3 ||
              data['revision'] is! String ||
              !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['revision'] as String) ||
              (revision != null && data['revision'] != revision)) {
            throw const FormatException(
              'Invalid sync page. Local data was preserved.',
            );
          }
          revision = data['revision'] as String;
          for (final key in _keys) {
            if (data[key] is! List ||
                (result[key] as List).length + (data[key] as List).length >
                    20000) {
              throw const FormatException(
                'Invalid sync page. Local data was preserved.',
              );
            }
            (result[key] as List).addAll(data[key] as List);
          }
          final next = data['nextCursor'];
          if (next != null &&
              (next is! int || next <= cursor! || next > 80000)) {
            throw const FormatException(
              'Invalid sync cursor. Local data was preserved.',
            );
          }
          cursor = next as int?;
        } while (cursor != null);
        return _decode(result);
      } on AuthException catch (error) {
        if (error.status != 409) rethrow;
      }
    }
    throw const FormatException(
      'Another device is syncing. Please try again; local changes are safe.',
    );
  }

  static const _keys = [
    'transactions',
    'recurring',
    'deletedTransactions',
    'deletedRecurring',
  ];
  static Iterable<Map<String, Object?>> _batches(MoneySyncData local) sync* {
    var batch = <String, List<Object?>>{for (final key in _keys) key: []};
    var size = 256;
    for (final entry in MoneyStore.encodeData(local).entries) {
      for (final value in entry.value! as List) {
        final bytes = utf8.encode(jsonEncode(value)).length + 1;
        if (bytes > 512 * 1024) {
          throw const FormatException(
            'A record is too large to sync. Local data was preserved.',
          );
        }
        if (size + bytes > 512 * 1024) {
          yield batch;
          batch = {for (final key in _keys) key: []};
          size = 256;
        }
        batch[entry.key]!.add(value);
        size += bytes;
      }
    }
    yield batch;
  }

  MoneySyncData _decode(Map<String, dynamic> data) {
    try {
      return MoneyStore.decodeData(data);
    } catch (_) {
      throw const FormatException(
        'The server returned invalid financial data. Your local data was preserved.',
      );
    }
  }
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

class AppUpdateService {
  const AppUpdateService({required this.baseUrl});
  static const currentVersionName = '260919.1';
  static const currentVersionCode = 260919001;
  static const _channel = MethodChannel('money_manager/update');
  static const maxApkBytes = 200 * 1024 * 1024;
  final String baseUrl;

  Future<UpdateInfo> checkLatest() async {
    final data = await apiRequest(baseUrl, '/api/update/latest');
    final base = serverUri(baseUrl, '');
    final apk = base.resolve(data['apkUrl'] as String? ?? '');
    final size = data['sizeBytes'];
    final code = data['versionCode'];
    final digest = data['sha256'];
    if (apk.origin != base.origin ||
        !apk.path.startsWith('/releases/') ||
        !apk.path.endsWith('.apk') ||
        apk.hasQuery ||
        apk.hasFragment ||
        apk.userInfo.isNotEmpty ||
        size is! int ||
        size <= 0 ||
        size > maxApkBytes ||
        code is! int ||
        code <= 0 ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException(
        'The update could not be verified. Please contact the server owner.',
      );
    }
    return UpdateInfo(
      available: code > currentVersionCode,
      versionName: data['versionName'] as String? ?? '',
      versionCode: code,
      apkUrl: apk.toString(),
      notes: data['notes'] as String? ?? '',
      sha256Digest: digest,
      sizeBytes: size,
    );
  }

  Future<String> downloadApk(
    UpdateInfo info, {
    void Function(double)? onProgress,
  }) async {
    final base = serverUri(baseUrl, '');
    final uri = Uri.parse(info.apkUrl);
    if (uri.origin != base.origin ||
        info.sizeBytes <= 0 ||
        info.sizeBytes > maxApkBytes) {
      throw const FormatException('Untrusted update download.');
    }
    final client = http.Client();
    final baseDir = Platform.isAndroid
        ? Directory((await _channel.invokeMethod<String>('getCacheDirectory'))!)
        : Directory.systemTemp;
    final directory = await Directory(
      '${baseDir.path}/money-manager-updates',
    ).create(recursive: true);
    final file = File('${directory.path}/update-${info.versionCode}.apk.part');
    IOSink? sink;
    try {
      final response = await client
          .send(http.Request('GET', uri)..followRedirects = false)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 ||
          (response.contentLength != null &&
              response.contentLength != info.sizeBytes)) {
        throw const FormatException(
          'Update download failed verification. Try again.',
        );
      }
      sink = file.openWrite();
      final timer = Stopwatch()..start();
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 15),
      )) {
        received += chunk.length;
        if (received > info.sizeBytes ||
            timer.elapsed > const Duration(minutes: 3)) {
          throw const FormatException(
            'Update download exceeded its limit. Try again.',
          );
        }
        sink.add(chunk);
        onProgress?.call(received / info.sizeBytes);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received != info.sizeBytes ||
          (await sha256.bind(file.openRead()).first).toString() !=
              info.sha256Digest) {
        throw const FormatException(
          'The update is incomplete or damaged. Please download it again.',
        );
      }
      final signature = await file.openRead(0, 4).expand((v) => v).toList();
      if (!listEquals(signature, [0x50, 0x4b, 0x03, 0x04])) {
        throw const FormatException('The downloaded file is not an APK.');
      }
      final target = File('${directory.path}/update-${info.versionCode}.apk');
      await file.rename(target.path);
      return target.path;
    } finally {
      client.close();
      await sink?.close();
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> installApk(String path) async {
    if (!Platform.isAndroid) {
      throw const FormatException('APK updates are available on Android only.');
    }
    await _channel.invokeMethod<void>('installApk', {'path': path});
  }
}
