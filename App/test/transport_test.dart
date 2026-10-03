import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:esp32_navride/src/transport.dart';

void main() {
  test('BLE packets fit 180 bytes after escaping and retain request IDs', () {
    for (final text in ['Nguyễn Huệ', '"' * 120, '\\' * 120, '🛵' * 120]) {
      final encoded = encodeDeviceCommand({
        'command': 'push_notification',
        'title': text,
        'body': text,
        'requestId': 2147483647,
      }, maxBytes: 180);
      expect(utf8.encode(encoded).length, lessThanOrEqualTo(180));
      final payload = jsonDecode(encoded) as Map;
      expect(payload['requestId'], 2147483647);
      expect(payload['apiVersion'], 1);
      expect(payload['command'], 'push_notification');
    }
  });

  test('credentials are byte-validated and never silently truncated', () {
    expect(() => validateWifiCredentials('é' * 17, ''), throwsFormatException);
    expect(
      () => validateWifiCredentials('SuBo', 'x' * 64),
      throwsFormatException,
    );
    final command = {
      'command': 'configure_wifi',
      'ssid': '"' * 32,
      'password': '"' * 63,
    };
    expect(
      () => encodeDeviceCommand(command, maxBytes: 180),
      throwsFormatException,
    );
    expect(
      (jsonDecode(encodeDeviceCommand(command)) as Map)['password'],
      '"' * 63,
    );
  });

  test('request IDs change and fit the firmware signed integer', () {
    final first = nextDeviceRequestId();
    final next = nextDeviceRequestId();
    expect(next, isNot(first));
    expect(next, inInclusiveRange(1, 2147483647));
  });

  test('HTTP 200 without positive acknowledgement is not delivery', () async {
    for (final body in ['{"ok":false}', '{}', '[]', '<html>Login</html>']) {
      final transport = NetworkTransport(
        '192.168.1.55',
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        transport.send({'command': 'ping'}),
        throwsFormatException,
      );
    }
  });

  test(
    'navigation text is sanitized but Wi-Fi names are not transliterated',
    () {
      final packet =
          jsonDecode(
                encodeDeviceCommand({
                  'command': 'navigation',
                  'street': 'Đường Nguyễn Huệ',
                  'distance_m': 999,
                }),
              )
              as Map;
      expect(packet['street'], 'Duong Nguyen Hue');
      expect(packet['distance_m'], 999);
      final credentials =
          jsonDecode(
                encodeDeviceCommand({
                  'command': 'configure_wifi',
                  'ssid': 'Nhà',
                  'password': '12345678',
                }),
              )
              as Map;
      expect(credentials['ssid'], 'Nhà');
    },
  );

  test('converts Vietnamese and smart punctuation to the TFT ASCII font', () {
    expect(
      toTftText('Thông báo: “Rẽ phải” – 250 m • ✅'),
      'Thong bao: "Re phai" - 250 m * v',
    );
  });

  test('handles decomposed accents and omits unsupported emoji', () {
    expect(toTftText('Tôi đi 🛵'), 'Toi di');
  });

  test(
    'maps common notification icons and direction arrows to ASCII hints',
    () {
      expect(toTftText('✅ Rẽ phải ➡️ 250 m'), 'v Re phai > 250 m');
    },
  );

  test(
    'transliterates Vietnamese display text while preserving commands',
    () async {
      Map<String, dynamic>? sent;
      final transport = NetworkTransport(
        '192.168.1.55',
        client: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"ok":true}', 200);
        }),
      );

      await transport.send({
        'command': 'push_notification',
        'title': 'Rẽ phải ở Đà Nẵng',
        'body': 'Công việc đã hoàn thành',
      });

      expect(sent?['command'], 'push_notification');
      expect(sent?['title'], 'Re phai o Da Nang');
      expect(sent?['body'], 'Cong viec da hoan thanh');
    },
  );

  test('normalizes a bare ESP32 IP and rejects unsafe URL shapes', () {
    expect(normalizeEsp32BaseUrl(' 192.168.1.55/ '), 'http://192.168.1.55');
    expect(
      () => normalizeEsp32BaseUrl('ftp://192.168.1.55'),
      throwsFormatException,
    );
    expect(
      () => normalizeEsp32BaseUrl('http://192.168.1.55/api/command'),
      throwsFormatException,
    );
  });

  test(
    'network transport reads health and sends a timestamped command',
    () async {
      Map<String, dynamic>? sent;
      final client = MockClient((request) async {
        if (request.url.path == '/api/health') {
          return http.Response(
            '{"connected":true,"mode":"wifi","ip":"192.168.1.55"}',
            200,
          );
        }
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      });
      final transport = NetworkTransport('192.168.1.55', client: client);

      final status = await transport.health();
      await transport.send({'command': 'push_notification', 'title': 'Test'});

      expect(status.connected, isTrue);
      expect(status.ip, '192.168.1.55');
      expect(sent?['apiVersion'], 1);
      expect(sent?['command'], 'push_notification');
      expect(sent?['timestamp'], isA<int>());
    },
  );

  test('network transport reports malformed ESP32 health data', () async {
    final transport = NetworkTransport(
      '192.168.1.55',
      client: MockClient((_) async => http.Response('not-json', 200)),
    );

    expect(
      transport.health,
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('JSON'),
        ),
      ),
    );
  });

  test('network transport sends Wi-Fi setup to the setup endpoint', () async {
    Uri? target;
    Map<String, dynamic>? sent;
    final transport = NetworkTransport(
      '192.168.4.1',
      client: MockClient((request) async {
        target = request.url;
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true}', 200);
      }),
    );

    await transport.setupWifi('SuBo', 'secret');

    expect(target?.path, '/api/setup');
    expect(sent, {'ssid': 'SuBo', 'password': 'secret'});
  });

  test('network transport rejects non-success responses', () async {
    final transport = NetworkTransport(
      '192.168.1.55',
      client: MockClient((_) async => http.Response('busy', 503)),
    );

    expect(
      () => transport.send({'command': 'clear_popup'}),
      throwsA(isA<Exception>()),
    );
  });
}
