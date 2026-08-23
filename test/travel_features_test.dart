import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vietnam_map_01/src/repositories/vietnam_regions.dart';
import 'package:vietnam_map_01/src/repositories/wishlist_repository.dart';

void main() {
  test('Vietnam map exposes all eight geographic regions', () {
    expect(VietnamRegions.all, hasLength(8));
    expect(VietnamRegions.forProvince('Hà Nội'), 'Đồng bằng sông Hồng');
    expect(VietnamRegions.forProvince('Hà Giang'), 'Đông Bắc Bộ');
    expect(VietnamRegions.forProvince('Tuyên Quang'), 'Đông Bắc Bộ');
    expect(VietnamRegions.forProvince('Đà Nẵng'), 'Duyên hải Nam Trung Bộ');
    expect(VietnamRegions.forProvince('Cà Mau'), 'Đồng bằng sông Cửu Long');
  });

  test('wishlist is local, deduplicated, and survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = WishlistRepository();

    await repository.save(['Đà Nẵng', 'Hà Nội', 'Đà Nẵng']);

    expect(await repository.load(), {'Đà Nẵng', 'Hà Nội'});
  });
}
