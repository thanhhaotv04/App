import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

const navRideServiceUuid = '7e6d0001-5b1a-4d8f-9a2c-320001000001';
const navRideCommandUuid = '7e6d0002-5b1a-4d8f-9a2c-320001000002';
const navRideStatusUuid = '7e6d0003-5b1a-4d8f-9a2c-320001000003';
int _requestSequence = DateTime.now().millisecondsSinceEpoch % 2147483647;

int nextDeviceRequestId() =>
    _requestSequence = (_requestSequence % 2147483647) + 1;

final _tftAccentMap = <int, int>{
  for (final entry in const {
    'a': 'àáảãạăằắẳẵặâầấẩẫậ',
    'A': 'ÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬ',
    'e': 'èéẻẽẹêềếểễệ',
    'E': 'ÈÉẺẼẸÊỀẾỂỄỆ',
    'i': 'ìíỉĩị',
    'I': 'ÌÍỈĨỊ',
    'o': 'òóỏõọôồốổỗộơờớởỡợ',
    'O': 'ÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢ',
    'u': 'ùúủũụưừứửữự',
    'U': 'ÙÚỦŨỤƯỪỨỬỮỰ',
    'y': 'ỳýỷỹỵ',
    'Y': 'ỲÝỶỸỴ',
    'd': 'đ',
    'D': 'Đ',
  }.entries)
    for (final rune in entry.value.runes) rune: entry.key.codeUnitAt(0),
  0x2013: 0x2D, // en dash -> -
  0x2014: 0x2D, // em dash -> -
  0x2212: 0x2D, // minus -> -
  0x2018: 0x27, // smart apostrophes -> '
  0x2019: 0x27,
  0x201C: 0x22, // smart quotes -> "
  0x201D: 0x22,
  0x2022: 0x2A, // bullet -> *
  0x2190: 0x3C, // arrows -> ASCII direction hints
  0x2191: 0x5E,
  0x2192: 0x3E,
  0x2193: 0x76,
  0x21B6: 0x55, // u-turn -> U
  0x27A1: 0x3E,
  0x2B05: 0x3C,
  0x2B06: 0x5E,
  0x2B07: 0x76,
  0x2611: 0x76, // check boxes/checkmarks -> v
  0x2713: 0x76,
  0x2714: 0x76,
  0x2705: 0x76,
  0x1F5F8: 0x76,
  0x26A0: 0x21, // warning/alert icons -> !
  0x2757: 0x21,
  0x1F514: 0x21, // bell -> !
  0x1F4CD: 0x40, // map pin -> @
};

String toTftText(String value) {
  final result = StringBuffer();
  var previousSpace = true;
  for (final rune in value.runes) {
    if ((rune >= 0x0300 && rune <= 0x036f) ||
        (rune >= 0x1ab0 && rune <= 0x1aff) ||
        (rune >= 0x1dc0 && rune <= 0x1dff) ||
        (rune >= 0x20d0 && rune <= 0x20ff) ||
        (rune >= 0xfe20 && rune <= 0xfe2f)) {
      continue;
    }
    if (rune >= 0xfe00 && rune <= 0xfe0f) continue;
    final ascii = rune >= 32 && rune <= 126 ? rune : _tftAccentMap[rune] ?? 32;
    if (ascii == 32) {
      if (!previousSpace) result.write(' ');
      previousSpace = true;
    } else {
      result.writeCharCode(ascii);
      previousSpace = false;
    }
  }
  return result.toString().trim();
}

Map<String, dynamic> _displaySafeCommand(Map<String, dynamic> command) => {
  for (final entry in command.entries)
    entry.key:
        {'title', 'body', 'street'}.contains(entry.key) && entry.value is String
        ? toTftText(entry.value as String)
        : entry.value,
};

String encodeDeviceCommand(Map<String, dynamic> command, {int maxBytes = 512}) {
  final payload = <String, dynamic>{
    ..._displaySafeCommand(command),
    'apiVersion': 1,
    'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  };
  var encoded = jsonEncode(payload);
  // These fields are display-only. Never truncate credentials or protocol data.
  for (final key in ['body', 'title', 'street']) {
    while (utf8.encode(encoded).length > maxBytes &&
        (payload[key] as String? ?? '').isNotEmpty) {
      final value = payload[key] as String;
      payload[key] = value.substring(0, value.length - 1);
      encoded = jsonEncode(payload);
    }
  }
  if (utf8.encode(encoded).length > maxBytes) {
    throw const FormatException(
      'Command is too large. Shorten the content or use Wi-Fi for network setup.',
    );
  }
  return encoded;
}

void validateWifiCredentials(String ssid, String password) {
  if (ssid.isEmpty ||
      utf8.encode(ssid).length > 32 ||
      utf8.encode(password).length > 63) {
    throw const FormatException(
      'Wi-Fi name must be 1–32 bytes and password at most 63 bytes.',
    );
  }
}

String normalizeEsp32BaseUrl(String value) {
  var normalized = value.trim();
  if (normalized.isEmpty) {
    throw const FormatException('Enter the ESP32 IP address.');
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
      'Invalid address. Example: http://192.168.1.55',
    );
  }
  return uri.replace(path: '').toString().replaceFirst(RegExp(r'/$'), '');
}

abstract class DeviceTransport {
  Future<DeviceStatus> health();
  Future<void> send(Map<String, dynamic> command);
  Future<void> setupWifi(String ssid, String password);
  Future<void> disconnect();
}

class DemoTransport implements DeviceTransport {
  @override
  Future<DeviceStatus> health() async =>
      const DeviceStatus(connected: false, mode: 'demo');

  @override
  Future<void> send(Map<String, dynamic> command) async {
    throw StateError('ESP32 is not connected. Nothing was sent.');
  }

  @override
  Future<void> setupWifi(String ssid, String password) async {
    throw StateError('Connect ESP32 before sending Wi-Fi settings.');
  }

  @override
  Future<void> disconnect() async {}
}

class NetworkTransport implements DeviceTransport {
  NetworkTransport(String baseUrl, {http.Client? client})
    : baseUrl = normalizeEsp32BaseUrl(baseUrl),
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<DeviceStatus> health() async {
    final response = await _client
        .get(_uri('/api/health'))
        .timeout(const Duration(seconds: 4));
    if (response.statusCode != 200) {
      throw Exception('ESP32 returned HTTP ${response.statusCode}.');
    }
    try {
      return DeviceStatus.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    } on FormatException {
      throw Exception('ESP32 returned invalid JSON.');
    } on TypeError {
      throw Exception('ESP32 returned an invalid response.');
    }
  }

  Future<void> _post(String path, Map<String, dynamic> body) async {
    final response = await _client
        .post(
          _uri(path),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('ESP32 rejected the command (${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['ok'] != true) {
      throw const FormatException('ESP32 did not confirm this command.');
    }
  }

  @override
  Future<void> send(Map<String, dynamic> command) => _post(
    '/api/command',
    jsonDecode(encodeDeviceCommand(command)) as Map<String, dynamic>,
  );

  @override
  Future<void> setupWifi(String ssid, String password) async {
    validateWifiCredentials(ssid, password);
    await _post('/api/setup', {'ssid': ssid, 'password': password});
  }

  @override
  Future<void> disconnect() async => _client.close();
}

class BleCandidate {
  const BleCandidate(this.device, this.name);

  final BluetoothDevice device;
  final String name;

  String get id => device.remoteId.str;
}

class BluetoothTransport implements DeviceTransport {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandCharacteristic;
  BluetoothCharacteristic? _statusCharacteristic;

  bool get isConnected => _device?.isConnected ?? false;

  Future<List<BleCandidate>> scan() async {
    if (!await FlutterBluePlus.isSupported) {
      throw Exception('Bluetooth LE is not supported on this device.');
    }
    final found = <String, BleCandidate>{};
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final name = result.advertisementData.advName.isNotEmpty
            ? result.advertisementData.advName
            : result.device.platformName;
        found[result.device.remoteId.str] = BleCandidate(
          result.device,
          name.isEmpty ? 'BLE device' : name,
        );
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(navRideServiceUuid)],
        timeout: const Duration(seconds: 8),
      );
      await FlutterBluePlus.isScanning
          .where((scanning) => !scanning)
          .first
          .timeout(const Duration(seconds: 10));
    } finally {
      await subscription.cancel();
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
    }
    return found.values.toList();
  }

  Future<void> connect(BluetoothDevice device) async {
    await disconnect();
    await device.connect(
      license: License.nonprofit,
      timeout: const Duration(seconds: 12),
    );
    _device = device;
    try {
      final services = await device.discoverServices();
      BluetoothCharacteristic? command;
      BluetoothCharacteristic? status;
      for (final service in services) {
        if (service.uuid == Guid(navRideServiceUuid)) {
          for (final characteristic in service.characteristics) {
            if (characteristic.uuid == Guid(navRideCommandUuid)) {
              command = characteristic;
            }
            if (characteristic.uuid == Guid(navRideStatusUuid)) {
              status = characteristic;
            }
          }
        }
      }
      if (command == null || status == null) {
        throw Exception('ESP32-NavRide command channel not found.');
      }
      await status.setNotifyValue(true);
      _commandCharacteristic = command;
      _statusCharacteristic = status;
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  Future<void> connectSaved(String remoteId) async {
    if (remoteId.trim().isEmpty) {
      throw Exception('Select a Bluetooth device first.');
    }
    await connect(BluetoothDevice.fromId(remoteId.trim()));
  }

  @override
  Future<DeviceStatus> health() async {
    if (!isConnected) throw Exception('Bluetooth is not connected.');
    final device = _device;
    return DeviceStatus(
      connected: true,
      mode: 'bluetooth',
      deviceName: device?.platformName.isNotEmpty == true
          ? device!.platformName
          : 'ESP32-NavRide',
    );
  }

  @override
  Future<void> send(Map<String, dynamic> command) async {
    final characteristic = _commandCharacteristic;
    final status = _statusCharacteristic;
    if (!isConnected || characteristic == null || status == null) {
      throw StateError('Bluetooth is not connected.');
    }
    final requestId = nextDeviceRequestId();
    final message = encodeDeviceCommand({
      ...command,
      'requestId': requestId,
    }, maxBytes: 180);
    final ack = status.onValueReceived
        .map((bytes) => utf8.decode(bytes, allowMalformed: true))
        .firstWhere(
          (value) =>
              value.startsWith('error:') || value.endsWith(':$requestId'),
        )
        .timeout(const Duration(seconds: 5))
        .then((value) {
          if (!value.startsWith('ok:')) {
            throw StateError('ESP32 rejected the command: $value');
          }
        });
    await Future.wait([
      characteristic.write(
        utf8.encode(message),
        withoutResponse: false,
        allowLongWrite: true,
      ),
      ack,
    ]);
  }

  @override
  Future<void> setupWifi(String ssid, String password) async {
    validateWifiCredentials(ssid, password);
    await send({
      'command': 'configure_wifi',
      'ssid': ssid,
      'password': password,
    });
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    _commandCharacteristic = null;
    _statusCharacteristic = null;
    _device = null;
    if (device != null) await device.disconnect();
  }
}

DeviceTransport transportFor(NavRideConfig config, BluetoothTransport ble) =>
    switch (config.mode) {
      ConnectionMode.demo => DemoTransport(),
      ConnectionMode.network => NetworkTransport(config.baseUrl),
      ConnectionMode.bluetooth => ble,
    };

bool get bluetoothAvailableOnWeb => kIsWeb;
