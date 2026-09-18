import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/models/checkin.dart';
import 'package:vietnam_map_01/src/repositories/checkin_repository.dart';
import 'package:vietnam_map_01/src/repositories/local_image_storage.dart';

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

  test(
    'a new signed-in account starts empty, without demo check-ins',
    () async {
      SharedPreferences.setMockInitialValues({'vmc-auth-user': 'NewUser'});
      expect(await CheckInRepository().load(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vnm_checkins'), isNull);
    },
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

  test('renaming an account retains copied photo references', () async {
    final originalDirectory = Directory.current;
    final tempDirectory = await Directory.systemTemp.createTemp('vmc-rename-');
    try {
      Directory.current = tempDirectory;
      SharedPreferences.setMockInitialValues({'vmc-auth-user': 'OldUser'});
      final oldRef = await LocalImageStorage.saveImage(
        bytes: [1, 2, 3],
        originalName: 'memory.jpg',
        city: 'Đà Lạt',
        createdAt: 1700000000000,
      );
      final photoItem = CheckInPhotoAsset(localPhoto: oldRef);
      await CheckInRepository(userName: 'OldUser').save([
        item.copyWith(localPhoto: oldRef, photos: [photoItem]),
      ]);

      await LocalImageStorage.moveUserData('OldUser', 'NewUser');
      await CheckInRepository.moveUserData('OldUser', 'NewUser');

      final moved = (await CheckInRepository(
        userName: 'NewUser',
      ).load()).single;
      expect(moved.localPhoto, isNot(oldRef));
      expect(moved.photoItems.single.localPhoto, moved.localPhoto);
      expect(await LocalImageStorage.readImage(moved.localPhoto), [1, 2, 3]);
      expect(await LocalImageStorage.readImage(oldRef), [1, 2, 3]);
    } finally {
      Directory.current = originalDirectory;
      await tempDirectory.delete(recursive: true);
    }
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
