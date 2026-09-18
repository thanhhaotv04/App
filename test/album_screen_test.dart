import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show ImageSource, XFile;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/models/checkin.dart';
import 'package:vietnam_map_01/src/repositories/album_repository.dart';
import 'package:vietnam_map_01/src/repositories/checkin_repository.dart';
import 'package:vietnam_map_01/src/models/travel_album.dart';
import 'package:vietnam_map_01/src/screens/album_screen.dart';
import 'package:vietnam_map_01/src/widgets/checkin_photo.dart';

void main() {
  testWidgets('legacy albums remain visible and new empty albums persist', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'traveler'});
    await CheckInRepository().save([
      const CheckIn(
        id: 'old-checkin',
        city: 'Lâm Đồng',
        place: 'Hồ Xuân Hương',
        notes: '',
        source: 'manual',
        synced: true,
        createdAt: 1700000000000,
        lat: 11.94,
        lng: 108.44,
        photo: 'user/Picture/traveler/DaLat/lake.jpg',
        album: 'Đà Lạt',
      ),
    ]);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AlbumScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Đà Lạt'), findsOneWidget);
    expect(find.text('1 photos · 1 check-ins'), findsOneWidget);

    await tester.tap(find.text('New album'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Album name'),
      'Miền Tây',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Miền Tây'), findsOneWidget);
    expect((await AlbumRepository().load()).single.name, 'Miền Tây');

    await tester.tap(find.text('Miền Tây'));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    await tester.tap(find.text('Add check-ins'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect((await AlbumRepository().load()).single.checkInIds, ['old-checkin']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('camera photo keeps its place and note in a themed album', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'traveler'});
    await AlbumRepository().upsert(
      const TravelAlbum(
        id: 'album-1',
        name: 'Đà Lạt',
        createdAt: 100,
        updatedAt: 100,
      ),
    );
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumScreen(
            pickPhotos: (source) async {
              expect(source, ImageSource.camera);
              return [XFile.fromData(imageBytes, name: 'lake.png')];
            },
            savePhoto: (file, albumName, place, createdAt) async {
              expect(file.name, isEmpty); // XFile.fromData ignores name on IO.
              expect(albumName, 'Đà Lạt');
              expect(place, 'Hồ Xuân Hương');
              return 'local:fake-lake.png';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đà Lạt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Place'),
      'Hồ Xuân Hương',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Note'),
      'Chiều bên hồ',
    );
    await tester.tap(find.text('Save to album'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Could not save this moment'), findsNothing);
    final photo = (await AlbumRepository().load()).single.photos.single;
    expect(photo.place, 'Hồ Xuân Hương');
    expect(photo.note, 'Chiều bên hồ');
    expect(photo.localPhoto, startsWith('local:'));
    expect(find.text('Hồ Xuân Hương'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting an album photo persists a sync tombstone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'traveler'});
    await AlbumRepository().upsert(
      const TravelAlbum(
        id: 'album-1',
        name: 'Miền Tây',
        createdAt: 100,
        updatedAt: 100,
        photos: [
          AlbumPhoto(
            id: 'photo-1',
            localPhoto: 'local:missing-photo.jpg',
            name: 'river.jpg',
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        home: const Scaffold(body: AlbumScreen()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Miền Tây'));
    await tester.pump(const Duration(milliseconds: 350));
    final photoTile = find.ancestor(
      of: find.byType(CheckInPhoto).first,
      matching: find.byType(InkWell),
    );
    await tester.ensureVisible(photoTile.first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(photoTile.first);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('Save to device'), findsOneWidget);
    await tester.tap(find.text('Delete photo'));
    await tester.pump();
    await tester.tap(find.text('Delete photo').last);
    await tester.pump(const Duration(milliseconds: 350));

    final album = (await AlbumRepository().load()).single;
    expect(album.photos, isEmpty);
    expect(album.deletedPhotoIds, ['photo-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleting a legacy album hides it but keeps its check-in', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'legacy-delete'});
    await CheckInRepository().save([
      const CheckIn(
        id: 'visit-1',
        city: 'Lâm Đồng',
        place: 'Hồ Xuân Hương',
        notes: 'Keep this',
        source: 'manual',
        synced: true,
        createdAt: 100,
        lat: 0,
        lng: 0,
        photo: '',
        album: 'Đà Lạt',
      ),
    ]);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AlbumScreen())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete album Đà Lạt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete album'));
    await tester.pumpAndSettle();
    expect(find.text('Đà Lạt'), findsNothing);
    expect((await AlbumRepository().load()).single.isDeleted, isTrue);
    expect((await CheckInRepository().load()).single.id, 'visit-1');
    expect(tester.takeException(), isNull);
  });

  testWidgets('individual check-in photo can be copied into album', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'vmc-auth-user': 'photo-import'});
    await CheckInRepository().save([
      CheckIn(
        id: 'visit-1',
        city: 'Lâm Đồng',
        place: 'Hồ Xuân Hương',
        notes: 'Golden hour',
        source: 'manual',
        synced: false,
        createdAt: 100,
        lat: 0,
        lng: 0,
        photo: '',
        photos: const [
          CheckInPhotoAsset(
            photo: 'user/Picture/photo-import/source.png',
            name: 'source.png',
          ),
        ],
      ),
    ]);
    await AlbumRepository().upsert(
      const TravelAlbum(
        id: 'trip',
        name: 'Đà Lạt',
        createdAt: 100,
        updatedAt: 100,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumScreen(
            copyCheckinPhoto: (photo, checkin, albumName, createdAt) async {
              expect(photo.name, 'source.png');
              expect(checkin.id, 'visit-1');
              expect(albumName, 'Đà Lạt');
              return 'copy:album-copy.png';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đà Lạt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('From Checkin'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photos').last);
    await tester.pumpAndSettle();

    final album = (await AlbumRepository().load()).single;
    expect(album.photos, hasLength(1));
    expect(album.photos.single.place, 'Hồ Xuân Hương');
    expect(album.photos.single.note, 'Golden hour');
    expect(album.photos.single.localPhoto, 'copy:album-copy.png');
    expect(
      (await CheckInRepository().load()).single.photoItems.single.photo,
      'user/Picture/photo-import/source.png',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected album photos can be removed before saving', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'selected-remove',
    });
    await AlbumRepository().upsert(
      const TravelAlbum(
        id: 'trip',
        name: 'Miền Tây',
        createdAt: 100,
        updatedAt: 100,
      ),
    );
    var savedCount = 0;
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL/nwAAAABJRU5ErkJggg==',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AlbumScreen(
            pickPhotos: (source) async => [
              XFile.fromData(imageBytes, name: 'one.png'),
              XFile.fromData(imageBytes, name: 'two.png'),
            ],
            savePhoto: (file, albumName, place, createdAt) async {
              savedCount += 1;
              return 'copy:photo-$savedCount.png';
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miền Tây'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove selected photo 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to album'));
    await tester.pumpAndSettle();
    expect(savedCount, 1);
    expect((await AlbumRepository().load()).single.photos, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
