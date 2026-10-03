import 'package:flutter_test/flutter_test.dart';

import 'package:esp32_navride/src/models.dart';

void main() {
  test('missing health state must not imply a connected ESP32', () {
    expect(DeviceStatus.fromJson({}).connected, isFalse);
  });
  test('snapshot round trips notices, tasks, and connection config', () {
    final snapshot = NavRideSnapshot(
      profileName: 'Hào',
      notices: [
        Notice(
          id: 'n1',
          title: 'Test',
          body: 'Content',
          createdAt: DateTime(2026, 9, 30),
        ),
      ],
      tasks: [
        TaskItem(
          id: 't1',
          title: 'Việc',
          createdAt: DateTime(2026, 9, 30),
          done: true,
        ),
      ],
      config: const NavRideConfig(
        mode: ConnectionMode.network,
        baseUrl: 'http://192.168.4.1',
        updateBaseUrl: 'http://192.168.1.10:3000',
      ),
    );

    final restored = NavRideSnapshot.decode(snapshot.encode());
    expect(restored.profileName, 'Hào');
    expect(restored.notices.single.body, 'Content');
    expect(restored.tasks.single.done, isTrue);
    expect(restored.config.mode, ConnectionMode.network);
    expect(restored.config.updateBaseUrl, 'http://192.168.1.10:3000');
  });

  test('legacy backgrounds are ignored without losing connection data', () {
    final restored = NavRideSnapshot.decode(
      '{"profileName":"Hào","notices":[],"tasks":[],"config":{"background":"ocean","mode":"bluetooth","bluetoothId":"saved-board"}}',
    );

    expect(restored.profileName, 'Hào');
    expect(restored.config.mode, ConnectionMode.bluetooth);
    expect(restored.config.bluetoothId, 'saved-board');
    expect(restored.config.toJson().containsKey('background'), isFalse);
    expect(restored.config.updateBaseUrl, isEmpty);
  });
}
