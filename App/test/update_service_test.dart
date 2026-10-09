import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:esp32_navride/src/update_service.dart';

void main() {
  test('normalizes a LAN update server URL', () {
    expect(
      normalizeUpdateBaseUrl('192.168.1.10:3000/'),
      'http://192.168.1.10:3000',
    );
    expect(
      () => normalizeUpdateBaseUrl('http://server.local/path'),
      throwsFormatException,
    );
  });

  test('accepts a verified newer update manifest', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/update/latest');
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'versionName': '1.1.0',
            'versionCode': 2,
            'apkUrl': '/releases/esp32-navride-1.1.0.apk',
            'notes': 'Improved connection stability.',
            'sizeBytes': 1024,
            'sha256': 'a' * 64,
          }),
        ),
        200,
      );
    });
    final service = AppUpdateService(
      baseUrl: 'http://192.168.1.10:3000',
      client: client,
    );

    final info = await service.checkLatest(currentVersionCode: 1);

    expect(info.available, isTrue);
    expect(
      info.apkUrl,
      'http://192.168.1.10:3000/releases/esp32-navride-1.1.0.apk',
    );
    expect(info.sizeBytes, 1024);
  });

  test('explains when the update server is unavailable', () async {
    final service = AppUpdateService(
      baseUrl: 'http://192.168.1.10:3000',
      client: MockClient((_) async => http.Response('', 503)),
    );
    await expectLater(
      service.checkLatest(currentVersionCode: 1),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('App updates are temporarily unavailable'),
        ),
      ),
    );
  });

  test('rejects an APK hosted on another origin', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'versionName': '1.1.0',
          'versionCode': 2,
          'apkUrl': 'https://example.com/releases/app.apk',
          'notes': '',
          'sizeBytes': 1024,
          'sha256': 'b' * 64,
        }),
        200,
      ),
    );
    final service = AppUpdateService(
      baseUrl: 'http://192.168.1.10:3000',
      client: client,
    );

    expect(
      () => service.checkLatest(currentVersionCode: 1),
      throwsFormatException,
    );
  });

  test('downloads only an APK with the expected SHA-256', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cache = await Directory.systemTemp.createTemp('esp32-update-test-');
    const channel = MethodChannel('esp32_navride/update');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => cache.path);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final bytes = [0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4];
    final service = AppUpdateService(
      baseUrl: 'http://192.168.1.10:3000',
      client: MockClient((_) async => http.Response.bytes(bytes, 200)),
    );
    UpdateInfo info(String digest) => UpdateInfo(
      available: true,
      versionName: '1.1.0',
      versionCode: 2,
      apkUrl: 'http://192.168.1.10:3000/releases/app.apk',
      notes: '',
      sha256Digest: digest,
      sizeBytes: bytes.length,
    );

    try {
      final path = await service.downloadApk(
        info(sha256.convert(bytes).toString()),
      );
      expect(await File(path).readAsBytes(), bytes);
      expect(() => service.downloadApk(info('0' * 64)), throwsFormatException);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await cache.delete(recursive: true);
    }
  });
}
