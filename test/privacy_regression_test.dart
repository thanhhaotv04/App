import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vietnam_map_01/src/models/checkin.dart';
import 'package:vietnam_map_01/src/models/travel_album.dart';
import 'package:vietnam_map_01/src/repositories/album_share_service.dart';
import 'package:vietnam_map_01/src/repositories/backend_config.dart';
import 'package:vietnam_map_01/src/repositories/credential_store.dart';
import 'package:vietnam_map_01/src/repositories/image_optimizer.dart';
import 'package:vietnam_map_01/src/repositories/local_image_storage.dart';
import 'package:vietnam_map_01/src/repositories/private_photo.dart';
import 'package:vietnam_map_01/src/repositories/privacy_settings.dart';
import 'package:vietnam_map_01/src/repositories/sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'vmc-auth-user': 'privacy-user',
    }),
  );

  test(
    'private photos reject foreign origins, unsafe paths and redirects',
    () async {
      const base = 'https://photos.example';
      for (final photo in [
        'https://attacker.example/user/Picture/alice/trip.jpg',
        '//attacker.example/user/Picture/alice/trip.jpg',
        'https://photos.example:8443/user/Picture/alice/trip.jpg',
        'https://user:password@photos.example/user/Picture/alice/trip.jpg',
        '/user/Picture/alice/%2e%2e%2ftrip.jpg',
        '/api/auth/login',
        '/user/Picture/alice/trip.jpg?token=secret',
      ]) {
        expect(
          () => BackendConfig.photoUri(base, photo),
          throwsFormatException,
        );
      }
      final calls = <Uri>[];
      final client = MockClient((request) async {
        calls.add(request.url);
        expect(request.followRedirects, isFalse);
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          '',
          302,
          headers: {'location': 'https://attacker.example/steal'},
        );
      });
      expect(
        await PrivatePhoto.read(
          baseUrl: base,
          photo: '/user/Picture/alice/trip.jpg',
          headers: {'Authorization': 'Bearer test-token'},
          client: client,
        ),
        isNull,
      );
      expect(calls, hasLength(1));
      await expectLater(
        PrivatePhoto.read(
          baseUrl: base,
          photo: 'https://attacker.example/user/Picture/alice/trip.jpg',
          headers: {},
          client: client,
        ),
        throwsFormatException,
      );
      expect(calls, hasLength(1));
      client.close();
    },
  );

  test(
    'backend allows trusted LAN HTTP and requires HTTPS outside it',
    () async {
      for (final url in [
        'http://127.0.0.1:3000',
        'http://192.168.1.20:3000',
        'http://10.0.0.1',
        'http://172.31.0.1',
        'https://server.example',
      ]) {
        await BackendConfig.saveUrl(url);
        expect(await BackendConfig.loadUrl(), url);
      }
      for (final url in [
        'http://server.example',
        'http://172.32.0.1',
        'http://192.168.1.999',
        'https://user:pass@server.example',
        'https://server.example?password=secret',
      ]) {
        await expectLater(BackendConfig.saveUrl(url), throwsFormatException);
      }
    },
  );

  test(
    'sessions stay in secure storage and are bound to their backend',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const store = CredentialStore();
      await BackendConfig.saveUrl('https://original.example');
      await store.saveSession(
        userName: 'privacy-user',
        password: 'private-password',
        token: 'private-token',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vmc-auth-password'), isNull);
      expect(prefs.getString('vmc-auth-token-fallback'), isNull);
      expect(await store.readToken(), 'private-token');
      await BackendConfig.saveUrl('https://another.example');
      expect(await store.readToken(), isEmpty);
      await expectLater(store.authHeaders(), throwsStateError);
      await BackendConfig.saveUrl('https://original.example');
      expect(await store.readToken(), 'private-token');
      await store.clearToken();
      expect(await store.readToken(), isEmpty);
    },
  );

  test(
    'small images lose metadata while orientation and transparency survive',
    () async {
      final source = img.Image(width: 4, height: 2);
      source.exif.imageIfd.orientation = 6;
      source.exif.imageIfd.imageDescription = 'Private camera owner';
      source.exif.gpsIfd[1] = img.IfdValueAscii('N');
      source.exif.gpsIfd[2] = img.IfdValueRational(1606, 100);
      final input = img.encodeJpg(source);
      expect(img.decodeJpg(input)!.exif.isEmpty, isFalse);
      final optimized = await const ImageOptimizer().optimize(
        input,
        'small.jpg',
      );
      final output = img.decodeImage(optimized.bytes)!;
      expect([output.width, output.height], [2, 4]);
      expect(output.exif.isEmpty, isTrue);
      final transparent = img.Image(width: 2, height: 2, numChannels: 4);
      final png = await const ImageOptimizer().optimize(
        img.encodePng(transparent),
        'icon.png',
      );
      expect(png.fileName, 'icon.png');
      expect(img.decodePng(png.bytes)!.getPixel(0, 0).a, 0);
      final animated = img.Image(width: 2, height: 2);
      animated.addFrame(img.Image(width: 2, height: 2));
      final gif = await const ImageOptimizer().optimize(
        img.encodeGif(animated),
        'animation.gif',
      );
      expect(gif.fileName, 'animation.gif');
      expect(img.decodeGif(gif.bytes)!.numFrames, 2);
    },
  );

  test(
    'local photo reads and deletes cannot escape the active account or follow symlinks',
    () async {
      final original = Directory.current;
      final temp = await Directory.systemTemp.createTemp('vmc-local-privacy-');
      Directory.current = temp;
      addTearDown(() async {
        Directory.current = original;
        await temp.delete(recursive: true);
      });
      final secret = File('${temp.path}/private.txt');
      await secret.writeAsString('private data');
      expect(await LocalImageStorage.readImage('local:${secret.path}'), isNull);
      await LocalImageStorage.deleteImage('local:${secret.path}');
      expect(await secret.exists(), isTrue);
      final ref = await LocalImageStorage.saveImage(
        bytes: [1, 2, 3],
        originalName: 'trip.jpg',
        city: 'Huế',
        createdAt: 1,
      );
      expect(await LocalImageStorage.readImage(ref), [1, 2, 3]);
      final link = Link('${await LocalImageStorage.folderPath()}/escape.jpg');
      await link.create(secret.path);
      expect(await LocalImageStorage.readImage('local:${link.path}'), isNull);
      SharedPreferences.setMockInitialValues({'vmc-auth-user': 'another-user'});
      expect(await LocalImageStorage.readImage(ref), isNull);
      await LocalImageStorage.deleteImage(ref);
      expect(await File(ref.substring('local:'.length)).exists(), isTrue);
    },
  );

  test('sync strips metadata from older photos before upload', () async {
    final source = img.Image(width: 2, height: 2);
    source.exif.imageIfd.imageDescription = 'Private camera owner';
    const item = CheckIn(
      id: 'upload',
      city: 'Huế',
      place: 'Đại Nội',
      notes: '',
      source: 'manual',
      synced: false,
      createdAt: 1,
      lat: 0,
      lng: 0,
      photo: '',
    );
    var checked = false;
    final client = MockClient((request) async {
      final body = request.bodyBytes;
      expect(
        utf8.decode(body, allowMalformed: true),
        isNot(contains('Private camera owner')),
      );
      expect(
        utf8.decode(body, allowMalformed: true),
        contains('filename="trip.jpg"'),
      );
      checked = true;
      return http.Response(
        jsonEncode(item.toJson()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    await SyncService(
      baseUrl: 'https://photos.example',
      token: 'test-token',
      client: client,
    ).push(item, photoBytes: img.encodeJpg(source), photoFileName: 'trip.jpg');
    expect(checked, isTrue);
    client.close();
  });

  test(
    'shared albums omit internal paths and hidden coordinates, preserve duplicate photo names',
    () async {
      final original = Directory.current;
      final temp = await Directory.systemTemp.createTemp('vmc-share-privacy-');
      Directory.current = temp;
      addTearDown(() async {
        Directory.current = original;
        await temp.delete(recursive: true);
      });
      final source = img.Image(width: 2, height: 2);
      source.exif.imageIfd.imageDescription = 'Private camera owner';
      final ref = await LocalImageStorage.saveImage(
        bytes: img.encodeJpg(source),
        originalName: 'same.jpg',
        city: 'Huế',
        createdAt: 1,
      );
      final album = TravelAlbum(
        id: 'private-id',
        name: 'Trip',
        createdAt: 1,
        updatedAt: 2,
        photos: [
          AlbumPhoto(id: 'first', localPhoto: ref, name: 'same.jpg'),
          AlbumPhoto(id: 'second', localPhoto: ref, name: 'same.jpg'),
        ],
      );
      const item = CheckIn(
        id: 'checkin-id',
        city: 'Huế',
        place: 'Đại Nội',
        notes: 'My trip',
        source: 'gps',
        synced: true,
        createdAt: 1,
        lat: 16.06,
        lng: 108.22,
        photo: '',
        hideLocation: true,
      );
      final bytes = await const AlbumShareService().buildArchive(
        album: album,
        linkedCheckIns: [item],
        baseUrl: 'https://photos.example',
      );
      final zip = ZipDecoder().decodeBytes(bytes);
      final metadata = utf8.decode(
        zip.findFile('album.json')!.content as List<int>,
      );
      expect(metadata, isNot(contains('local:')));
      expect(metadata, isNot(contains('user/Picture/')));
      expect(metadata, isNot(contains('localPhoto')));
      expect(metadata, isNot(contains('16.06')));
      expect(metadata, contains('My trip'));
      final emptyAlbum = album.copyWith(photos: []);
      final visible = item.copyWith(hideLocation: false);
      final normal = ZipDecoder().decodeBytes(
        await const AlbumShareService().buildArchive(
          album: emptyAlbum,
          linkedCheckIns: [visible],
          baseUrl: 'https://photos.example',
        ),
      );
      expect(
        utf8.decode(normal.findFile('album.json')!.content as List<int>),
        contains('16.06'),
      );
      await const PrivacySettings(hideLocation: true).save();
      final hidden = ZipDecoder().decodeBytes(
        await const AlbumShareService().buildArchive(
          album: emptyAlbum,
          linkedCheckIns: [visible],
          baseUrl: 'https://photos.example',
        ),
      );
      expect(
        utf8.decode(hidden.findFile('album.json')!.content as List<int>),
        isNot(contains('16.06')),
      );

      expect(zip.files.map((file) => file.name).toSet(), hasLength(3));
      for (final file in zip.files.where(
        (file) => file.name.startsWith('photos/'),
      )) {
        expect(
          img
              .decodeImage(Uint8List.fromList(file.content as List<int>))!
              .exif
              .isEmpty,
          isTrue,
        );
      }
    },
  );
}
