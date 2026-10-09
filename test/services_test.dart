import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:task_reminder/src/models.dart';
import 'package:task_reminder/src/services.dart';

void main() {
  test(
    'logout accepts already expired sessions but keeps offline failures retryable',
    () async {
      await AuthService(
        baseUrl: 'https://tasks.example',
        client: MockClient(
          (_) async => http.Response('{"error":"invalid_session"}', 401),
        ),
      ).logout('expired');
      await expectLater(
        AuthService(
          baseUrl: 'https://tasks.example',
          client: MockClient(
            (_) async => http.Response('{"error":"unavailable"}', 503),
          ),
        ).logout('active'),
        throwsA(isA<AuthException>()),
      );
    },
  );
  test(
    'expired bearer sessions are renewed once and server merge is returned',
    () async {
      var logins = 0;
      final now = DateTime.utc(2026, 9, 22);
      final serverTask = TaskItem(
        id: 'server',
        title: 'Concurrent change',
        createdAt: now,
        updatedAt: now,
      );
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          logins++;
          return http.Response(
            jsonEncode({'name': 'Alice', 'token': 'renewed'}),
            200,
          );
        }
        if (request.headers['authorization'] == 'Bearer expired') {
          return http.Response('{"error":"invalid_session"}', 401);
        }
        return http.Response(
          jsonEncode({
            'tasks': request.method == 'GET' ? [] : [serverTask.toJson()],
            'assignments': [],
          }),
          200,
        );
      });
      final service = TaskSyncService(
        baseUrl: 'https://tasks.example',
        userName: 'Alice',
        password: 'password-123',
        token: 'expired',
        client: client,
      );
      final result = await service.syncTwoWay([], []);
      expect(logins, 1);
      expect(service.sessionToken, 'renewed');
      expect(result.tasks.single.id, 'server');
    },
  );

  test(
    'APK with altered bytes is rejected despite a successful HTTP response',
    () async {
      final client = MockClient((request) async {
        expect(request.followRedirects, isFalse);
        return http.Response('tampered', 200);
      });
      final service = AppUpdateService(
        baseUrl: 'https://tasks.example',
        client: client,
      );
      final info = UpdateInfo(
        available: true,
        versionName: 'next',
        versionCode: 8,
        apkUrl: 'https://tasks.example/app.apk',
        notes: '',
        size: 8,
        sha256Digest: sha256.convert(utf8.encode('original')).toString(),
      );
      await expectLater(service.downloadApk(info), throwsFormatException);
    },
  );

  test('credentials are never forwarded by HTTP redirects', () async {
    final client = MockClient((request) async {
      expect(request.followRedirects, isFalse);
      return http.Response(
        '{"message":"redirect"}',
        302,
        headers: {'location': 'https://evil.example'},
      );
    });
    await expectLater(
      AuthService(
        baseUrl: 'https://tasks.example',
        client: client,
      ).signIn('Alice', 'password-123'),
      throwsA(isA<AuthException>()),
    );
  });
  test(
    'sync exchanges the password once and then uses a bearer session',
    () async {
      final now = DateTime.utc(2026, 9, 22);
      final deleted = TaskItem(
        id: 'task-1',
        title: 'Deleted task',
        createdAt: now,
        updatedAt: now,
        deletedAt: now,
      );
      final client = MockClient((request) async {
        if (request.url.path == '/api/auth/login') {
          expect(
            jsonDecode(request.body),
            containsPair('password', 'password-123'),
          );
          return http.Response(
            jsonEncode({'name': 'hao', 'token': 'secure-session-token'}),
            200,
          );
        }
        expect(request.headers['authorization'], 'Bearer secure-session-token');
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({'tasks': [], 'assignments': []}),
            200,
          );
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect((body['tasks'] as List).single['deletedAt'], isNotNull);
        return http.Response(jsonEncode(body), 200);
      });
      final service = TaskSyncService(
        baseUrl: 'https://tasks.example',
        userName: 'hao',
        password: 'password-123',
        client: client,
      );

      final result = await service.syncTwoWay([deleted], const []);

      expect(service.sessionToken, 'secure-session-token');
      expect(result.tasks.single.isDeleted, isTrue);
    },
  );

  test(
    'update download verifies size and SHA-256 before returning the APK',
    () async {
      final bytes = utf8.encode('verified-apk');
      final digest = sha256.convert(bytes).toString();
      final client = MockClient((request) async {
        if (request.url.path == '/api/update/latest') {
          return http.Response(
            jsonEncode({
              'versionName': '1.0.7',
              'versionCode': 8,
              'apkUrl': '/releases/app.apk',
              'notes': 'Security update',
              'sha256': digest,
              'size': bytes.length,
            }),
            200,
          );
        }
        return http.Response.bytes(bytes, 200);
      });
      final service = AppUpdateService(
        baseUrl: 'https://tasks.example',
        client: client,
        currentBuildNumber: 7,
      );

      final info = await service.checkLatest();
      final path = await service.downloadApk(info);

      expect(info.available, isTrue);
      expect(await File(path).readAsBytes(), bytes);
      await File(path).delete();
    },
  );

  test('update check rejects an APK hosted on another origin', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'versionName': '9.9.9',
          'versionCode': 999,
          'apkUrl': 'https://evil.example/app.apk',
          'sha256': List.filled(64, 'a').join(),
          'size': 100,
        }),
        200,
      ),
    );
    final service = AppUpdateService(
      baseUrl: 'https://tasks.example',
      client: client,
      currentBuildNumber: 7,
    );

    expect(service.checkLatest(), throwsFormatException);
  });
}
