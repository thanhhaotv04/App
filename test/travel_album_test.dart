import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietnam_map_01/src/models/travel_album.dart';
import 'package:vietnam_map_01/src/repositories/album_repository.dart';

void main() {
  test('album records and standalone photos survive serialization', () {
    const album = TravelAlbum(
      id: 'album-1',
      name: 'Đà Lạt',
      createdAt: 100,
      updatedAt: 200,
      checkInIds: ['checkin-1'],
      photos: [
        AlbumPhoto(
          id: 'photo-1',
          localPhoto: 'local:photo.jpg',
          name: 'Garden.jpg',
          place: 'Vườn hoa',
          note: 'Buổi sáng nhiều nắng',
          createdAt: 150,
        ),
      ],
    );
    final restored = TravelAlbum.fromJson(album.toJson());
    expect(restored.name, 'Đà Lạt');
    expect(restored.checkInIds, ['checkin-1']);
    expect(restored.photos.single.localPhoto, 'local:photo.jpg');
    expect(restored.photos.single.place, 'Vườn hoa');
    expect(restored.photos.single.note, 'Buổi sáng nhiều nắng');
    expect(TravelAlbum.fromJson({'id': 'old', 'name': 'Old'}).photos, isEmpty);
  });

  test('albums stay in the account and move when username changes', () async {
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'Alice'});
    const album = TravelAlbum(
      id: 'album-1',
      name: 'Miền Tây',
      createdAt: 100,
      updatedAt: 100,
    );
    await AlbumRepository().upsert(album);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vmc-auth-user', 'Bob');
    expect(await AlbumRepository().load(), isEmpty);
    await AlbumRepository.moveUserData('Alice', 'Alicia');
    await prefs.setString('vmc-auth-user', 'Alicia');
    expect((await AlbumRepository().load()).single.name, 'Miền Tây');
    await prefs.setString('vmc-auth-user', 'Alice');
    expect(await AlbumRepository().load(), isEmpty);
  });

  test(
    'deleted album photos stay deleted while account data is merged',
    () async {
      SharedPreferences.setMockInitialValues({'vmc-auth-user': 'Alice'});
      await AlbumRepository(userName: 'Alice').upsert(
        const TravelAlbum(
          id: 'trip',
          name: 'Đà Lạt',
          createdAt: 100,
          updatedAt: 300,
          deletedPhotoIds: ['photo-1'],
        ),
      );
      await AlbumRepository(userName: 'Alicia').upsert(
        const TravelAlbum(
          id: 'trip',
          name: 'Đà Lạt',
          createdAt: 100,
          updatedAt: 200,
          photos: [
            AlbumPhoto(id: 'photo-1', photo: 'user/Picture/Alice/old.jpg'),
          ],
        ),
      );

      await AlbumRepository.moveUserData('Alice', 'Alicia');
      final result = (await AlbumRepository(userName: 'Alicia').load()).single;
      expect(result.photos, isEmpty);
      expect(result.deletedPhotoIds, ['photo-1']);
    },
  );

  test(
    'deleted albums survive account merge without restoring old photos',
    () async {
      SharedPreferences.setMockInitialValues({'vmc-auth-user': 'Alice'});
      await AlbumRepository(userName: 'Alice').upsert(
        const TravelAlbum(
          id: 'trip',
          name: 'Đà Lạt',
          createdAt: 100,
          updatedAt: 300,
          isDeleted: true,
        ),
      );
      await AlbumRepository(userName: 'Alicia').upsert(
        const TravelAlbum(
          id: 'trip',
          name: 'Đà Lạt',
          createdAt: 100,
          updatedAt: 200,
          photos: [AlbumPhoto(id: 'old', photo: 'old.jpg')],
        ),
      );
      await AlbumRepository.moveUserData('Alice', 'Alicia');
      final result = (await AlbumRepository(userName: 'Alicia').load()).single;
      expect(result.isDeleted, isTrue);
      expect(result.photos, isEmpty);
    },
  );
}
