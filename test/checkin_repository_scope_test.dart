import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/models/checkin.dart';
import 'package:vietnam_map_01/src/repositories/checkin_repository.dart';

void main() {
  final item = CheckIn(
    id: 'alice-memory',
    city: 'Đà Nẵng',
    place: 'Cầu Rồng',
    notes: 'Private memory',
    source: 'manual',
    synced: false,
    createdAt: 1700000000000,
    lat: 16.0544,
    lng: 108.2022,
    photo: '',
  );

  test('check-ins are stored under the signed-in username', () async {
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'Alice'});

    await CheckInRepository().save([item]);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vmc-auth-user', 'Bob');
    final bob = CheckInRepository();
    await bob.save([]);
    expect(await bob.load(), isEmpty);

    await prefs.setString('vmc-auth-user', 'Alice');
    expect((await CheckInRepository().load()).single.id, item.id);
  });

  test(
    'legacy unscoped data is assigned once and not shown to another user',
    () async {
      SharedPreferences.setMockInitialValues({
        'vmc-auth-user': 'Alice',
        'vnm_checkins': jsonEncode([item.toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();
      final alice = await CheckInRepository().load();
      expect(alice.single.id, item.id);

      await prefs.setString('vmc-auth-user', 'Bob');
      await CheckInRepository().save([]);
      expect(await CheckInRepository().load(), isEmpty);
    },
  );
}
