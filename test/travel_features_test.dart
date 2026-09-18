import 'package:flutter_test/flutter_test.dart';

import 'package:vietnam_map_01/src/repositories/vietnam_regions.dart';

void main() {
  test('Vietnam map exposes all eight geographic regions', () {
    expect(VietnamRegions.all, hasLength(8));
    expect(VietnamRegions.forProvince('Hà Nội'), 'Đồng bằng sông Hồng');
    expect(VietnamRegions.forProvince('Hà Giang'), 'Đông Bắc Bộ');
    expect(VietnamRegions.forProvince('Tuyên Quang'), 'Đông Bắc Bộ');
    expect(VietnamRegions.forProvince('Đà Nẵng'), 'Duyên hải Nam Trung Bộ');
    expect(VietnamRegions.forProvince('Cà Mau'), 'Đồng bằng sông Cửu Long');
  });
}
