import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietnam_map_01/src/models/checkin.dart';
import 'package:vietnam_map_01/src/repositories/backup_service.dart';
import 'package:vietnam_map_01/src/repositories/checkin_repository.dart';
import 'package:vietnam_map_01/src/repositories/sync_queue_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypted backup round-trips and rejects a wrong password', () async {
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'backup-user'});
    const item = CheckIn(
      id: 'memory-1',
      city: 'Đà Nẵng',
      place: 'Cầu Rồng',
      notes: 'Night walk',
      source: 'manual',
      synced: false,
      createdAt: 100,
      lat: 16.06,
      lng: 108.22,
      photo: '',
    );
    final bytes = await const BackupService().encode(
      checkIns: [item],
      albums: const [],
      password: 'strong-password',
      includeImages: false,
    );
    expect(bytes, isNotEmpty);
    final restored = await const BackupService().decode(
      Uint8List.fromList(bytes),
      'strong-password',
    );
    expect(restored.checkIns.single.place, 'Cầu Rồng');
    await expectLater(
      const BackupService().decode(bytes, 'wrong-password'),
      throwsFormatException,
    );
  });

  test(
    'offline delete replaces a pending upload and does not resurrect',
    () async {
      SharedPreferences.setMockInitialValues({'vmc-auth-user': 'queue-user'});
      final repository = CheckInRepository();
      const item = CheckIn(
        id: 'offline-1',
        city: 'Huế',
        place: 'Đại Nội',
        notes: '',
        source: 'manual',
        synced: false,
        createdAt: 100,
        lat: 0,
        lng: 0,
        photo: '',
      );
      await repository.add(item);
      await repository.remove(item.id);
      final operations = await const SyncQueueRepository().loadOperations();
      expect(operations, hasLength(1));
      expect(operations.single.type.name, 'deleteCheckIn');
      expect(await repository.load(), isEmpty);
    },
  );
}
