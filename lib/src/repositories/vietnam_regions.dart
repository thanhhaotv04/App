/// The eight geographic regions used by the Vietnamese administrative dataset.
///
/// The map asset in this app still contains the familiar 63-province view, so
/// this grouping deliberately keeps those names while giving users a useful
/// north-to-south progress view.
class VietnamRegion {
  const VietnamRegion({required this.name, required this.provinces});

  final String name;
  final List<String> provinces;
}

class VietnamRegions {
  const VietnamRegions._();

  static const all = <VietnamRegion>[
    VietnamRegion(
      name: 'Đông Bắc Bộ',
      provinces: [
        'Bắc Giang',
        'Bắc Kạn',
        'Cao Bằng',
        'Hà Giang',
        'Lạng Sơn',
        'Quảng Ninh',
        'Thái Nguyên',
        'Tuyên Quang',
      ],
    ),
    VietnamRegion(
      name: 'Tây Bắc Bộ',
      provinces: [
        'Điện Biên',
        'Hoà Bình',
        'Lai Châu',
        'Lào Cai',
        'Sơn La',
        'Yên Bái',
      ],
    ),
    VietnamRegion(
      name: 'Đồng bằng sông Hồng',
      provinces: [
        'Bắc Ninh',
        'Hà Nam',
        'Hà Nội',
        'Hải Dương',
        'Hải Phòng',
        'Hưng Yên',
        'Nam Định',
        'Ninh Bình',
        'Phú Thọ',
        'Thái Bình',
        'Vĩnh Phúc',
      ],
    ),
    VietnamRegion(
      name: 'Bắc Trung Bộ',
      provinces: [
        'Hà Tĩnh',
        'Nghệ An',
        'Quảng Bình',
        'Quảng Trị',
        'Thanh Hoá',
        'Thừa Thiên Huế',
      ],
    ),
    VietnamRegion(
      name: 'Duyên hải Nam Trung Bộ',
      provinces: [
        'Bình Định',
        'Bình Thuận',
        'Đà Nẵng',
        'Khánh Hoà',
        'Ninh Thuận',
        'Phú Yên',
        'Quảng Nam',
        'Quảng Ngãi',
      ],
    ),
    VietnamRegion(
      name: 'Tây Nguyên',
      provinces: ['Đắk Lắk', 'Đắk Nông', 'Gia Lai', 'Kon Tum', 'Lâm Đồng'],
    ),
    VietnamRegion(
      name: 'Đông Nam Bộ',
      provinces: [
        'Bà Rịa - Vũng Tàu',
        'Bình Dương',
        'Bình Phước',
        'Đồng Nai',
        'Tây Ninh',
        'TP.Hồ Chí Minh',
      ],
    ),
    VietnamRegion(
      name: 'Đồng bằng sông Cửu Long',
      provinces: [
        'An Giang',
        'Bạc Liêu',
        'Bến Tre',
        'Cà Mau',
        'Cần Thơ',
        'Đồng Tháp',
        'Hậu Giang',
        'Kiên Giang',
        'Long An',
        'Sóc Trăng',
        'Tiền Giang',
        'Trà Vinh',
        'Vĩnh Long',
      ],
    ),
  ];

  static String normalize(String value) {
    const from =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ'
        'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const to =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd'
        'AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    var result = value.trim();
    for (var i = 0; i < from.length; i += 1) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result
        .toLowerCase()
        .replaceFirst(RegExp(r'^tp\.?\s*'), '')
        .replaceFirst(RegExp(r'^thanh pho\s+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static String? forProvince(String province) {
    final normalized = normalize(province);
    if (normalized.isEmpty) return null;
    for (final region in all) {
      for (final candidate in region.provinces) {
        final candidateNormalized = normalize(candidate);
        if (normalized == candidateNormalized ||
            normalized.contains(candidateNormalized) ||
            candidateNormalized.contains(normalized)) {
          return region.name;
        }
      }
    }
    return null;
  }
}
