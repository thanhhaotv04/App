import 'package:flutter_test/flutter_test.dart';
import 'package:vietnam_map_01/src/models/checkin.dart';

void main() {
  test('loads legacy check-in JSON with safe metadata defaults', () {
    final item = CheckIn.fromJson({
      'id': 'legacy-1',
      'city': 'Hà Nội',
      'place': 'Hồ Hoàn Kiếm',
      'notes': 'Morning walk',
      'source': 'manual',
      'synced': true,
      'createdAt': 123,
      'lat': 21.0285,
      'lng': 105.8542,
      'photo': '',
    });

    expect(item.favorite, isFalse);
    expect(item.rating, 0);
    expect(item.tags, isEmpty);
    expect(item.toJson()['tags'], isEmpty);
  });

  test('normalizes new memory metadata', () {
    final item = CheckIn.fromJson({
      'id': 'new-1',
      'city': 'Đà Nẵng',
      'place': 'Cầu Rồng',
      'notes': 'Sunset',
      'source': 'gps',
      'synced': 'true',
      'createdAt': 456,
      'lat': 16.0544,
      'lng': 108.2022,
      'photo': '',
      'favorite': 'true',
      'rating': 9,
      'tags': ' food, sunset, food ',
    });

    expect(item.favorite, isTrue);
    expect(item.rating, 5);
    expect(item.tags, ['food', 'sunset']);
    expect(item.tagLine, 'food, sunset');
  });

  test('keeps legacy photo fields and reads an album gallery', () {
    final legacy = CheckIn.fromJson({
      'id': 'legacy-photo',
      'city': 'Hà Nội',
      'place': 'Hồ Tây',
      'photo': 'user/Picture/Alice/Hà Nội/photo.jpg',
    });
    expect(legacy.photoCount, 1);
    expect(legacy.photoItems.single.photo, legacy.photo);

    final album = CheckIn.fromJson({
      'id': 'trip-1',
      'city': 'Đà Nẵng',
      'place': 'Biển Mỹ Khê',
      'album': 'Đà Nẵng summer',
      'photos': [
        {'photo': 'user/Picture/Alice/Đà Nẵng summer/Đà Nẵng/a.jpg'},
        {'photo': 'user/Picture/Alice/Đà Nẵng summer/Đà Nẵng/b.jpg'},
      ],
    });
    expect(album.album, 'Đà Nẵng summer');
    expect(album.photoCount, 2);
    expect(album.toJson()['photo'], album.photoItems.first.photo);
    expect((album.toJson()['photos'] as List).length, 2);
  });
}
