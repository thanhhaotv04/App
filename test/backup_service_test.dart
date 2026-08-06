import 'package:flutter_test/flutter_test.dart';
import 'package:vietnam_map_01/src/models/checkin.dart';
import 'package:vietnam_map_01/src/repositories/backup_service.dart';

void main() {
  const service = BackupService();

  CheckIn item(String id, int createdAt) {
    return CheckIn(
      id: id,
      city: 'Hà Nội',
      place: 'Hồ Hoàn Kiếm',
      notes: 'Backup test',
      source: 'manual',
      synced: true,
      createdAt: createdAt,
      lat: 21.0285,
      lng: 105.8542,
      photo: '',
      favorite: true,
      rating: 4,
      tags: const ['backup'],
    );
  }

  test('encodes and decodes portable backup payload', () {
    final raw = service.encode([item('one', 10)], exportedAt: DateTime(2026));
    final decoded = service.decode(raw);

    expect(decoded, hasLength(1));
    expect(decoded.single.id, 'one');
    expect(decoded.single.favorite, isTrue);
    expect(decoded.single.tags, ['backup']);
  });

  test('merges imported backup by id and newest createdAt', () {
    final merged = service.merge(
      [item('same', 10), item('local', 20)],
      [item('same', 30), item('remote', 15)],
    );

    expect(merged.map((entry) => entry.id), ['same', 'local', 'remote']);
    expect(merged.first.createdAt, 30);
  });

  test('rejects malformed backup payloads', () {
    expect(() => service.decode('{"hello": true}'), throwsFormatException);
  });
}
