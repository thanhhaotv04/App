import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/repositories/auth_service.dart';
import 'package:vietnam_map_01/src/repositories/checkin_repository.dart';
import 'package:vietnam_map_01/src/repositories/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh local account restores existing backend check-ins', () async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'traveler',
      'vmc-auth-password': 'correct-password',
    });
    var unexpectedPosts = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/auth/login') {
        final body = jsonDecode(request.body) as Map;
        if (body['name'] == 'traveler' &&
            body['password'] == 'correct-password') {
          return http.Response(
            jsonEncode({'ok': true, 'name': 'traveler'}),
            200,
          );
        }
        return http.Response(jsonEncode({'error': 'incorrect_password'}), 401);
      }
      if (request.url.path == '/api/checkins' && request.method == 'GET') {
        expect(request.headers['X-User-Name'], 'traveler');
        expect(request.headers['X-Password'], 'correct-password');
        return http.Response(
          jsonEncode([
            {
              'id': 'existing-memory',
              'city': 'Đà Lạt',
              'place': 'Hồ Xuân Hương',
              'notes': '',
              'source': 'manual',
              'synced': true,
              'createdAt': 1700000000000,
              'lat': 11.94,
              'lng': 108.44,
              'photo': '',
            },
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      unexpectedPosts++;
      return http.Response('{}', 404);
    });

    const baseUrl = 'http://example.invalid';
    final repository = CheckInRepository();
    expect(await repository.load(), isEmpty);
    expect(
      await AuthService(
        baseUrl: baseUrl,
        client: client,
      ).login('traveler', 'correct-password'),
      'traveler',
    );
    final restored = await SyncService(
      baseUrl: baseUrl,
      client: client,
    ).syncTwoWay(await repository.load());
    await repository.save(restored);
    expect((await CheckInRepository().load()).single.id, 'existing-memory');
    expect(unexpectedPosts, 0);

    await expectLater(
      AuthService(
        baseUrl: baseUrl,
        client: client,
      ).login('traveler', 'wrong-password'),
      throwsA(isA<AuthException>()),
    );
  });
}
