class CheckInPhotoAsset {
  const CheckInPhotoAsset({
    this.photo = '',
    this.localPhoto = '',
    this.name = '',
    this.createdAt = 0,
  });

  final String photo;
  final String localPhoto;
  final String name;
  final int createdAt;

  CheckInPhotoAsset copyWith({
    String? photo,
    String? localPhoto,
    String? name,
    int? createdAt,
  }) {
    return CheckInPhotoAsset(
      photo: photo ?? this.photo,
      localPhoto: localPhoto ?? this.localPhoto,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get hasPhoto => photo.isNotEmpty || localPhoto.isNotEmpty;

  factory CheckInPhotoAsset.fromJson(Map<String, dynamic> json) {
    return CheckInPhotoAsset(
      photo: json['photo']?.toString() ?? '',
      localPhoto: json['localPhoto']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'photo': photo,
    'localPhoto': localPhoto,
    'name': name,
    'createdAt': createdAt,
  };
}

class CheckIn {
  const CheckIn({
    required this.id,
    required this.city,
    required this.place,
    required this.notes,
    required this.source,
    required this.synced,
    required this.createdAt,
    required this.lat,
    required this.lng,
    required this.photo,
    this.localPhoto = '',
    this.album = '',
    this.photos = const [],
    this.favorite = false,
    this.rating = 0,
    this.tags = const [],
  });

  final String id;
  final String city;
  final String place;
  final String notes;
  final String source;
  final bool synced;
  final int createdAt;
  final double lat;
  final double lng;
  final String photo;
  final String localPhoto;
  final String album;
  final List<CheckInPhotoAsset> photos;
  final bool favorite;
  final int rating;
  final List<String> tags;

  CheckIn copyWith({
    String? city,
    String? place,
    String? notes,
    String? source,
    bool? synced,
    int? createdAt,
    double? lat,
    double? lng,
    String? photo,
    String? localPhoto,
    String? album,
    List<CheckInPhotoAsset>? photos,
    bool? favorite,
    int? rating,
    List<String>? tags,
  }) {
    return CheckIn(
      id: id,
      city: city ?? this.city,
      place: place ?? this.place,
      notes: notes ?? this.notes,
      source: source ?? this.source,
      synced: synced ?? this.synced,
      createdAt: createdAt ?? this.createdAt,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      photo: photo ?? this.photo,
      localPhoto: localPhoto ?? this.localPhoto,
      album: album ?? this.album,
      photos: photos ?? this.photos,
      favorite: favorite ?? this.favorite,
      rating: rating ?? this.rating,
      tags: tags ?? this.tags,
    );
  }

  List<CheckInPhotoAsset> get photoItems {
    if (photos.isNotEmpty) return List.unmodifiable(photos);
    if (localPhoto.isEmpty && photo.isEmpty) return const [];
    return [
      CheckInPhotoAsset(
        photo: photo,
        localPhoto: localPhoto,
        createdAt: createdAt,
      ),
    ];
  }

  CheckInPhotoAsset? get primaryPhoto =>
      photoItems.isEmpty ? null : photoItems.first;
  int get photoCount => photoItems.length;
  bool get hasPhoto => photoItems.isNotEmpty;
  bool get isRated => rating > 0;
  String get tagLine => tags.join(', ');

  CheckIn withoutPhoto() => CheckIn(
    id: id,
    city: city,
    place: place,
    notes: notes,
    source: source,
    synced: false,
    createdAt: createdAt,
    lat: lat,
    lng: lng,
    photo: '',
    localPhoto: '',
    album: album,
    photos: const [],
    favorite: favorite,
    rating: rating,
    tags: tags,
  );

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final legacyPhoto = json['photo']?.toString() ?? '';
    final legacyLocalPhoto = json['localPhoto']?.toString() ?? '';
    final decodedPhotos = _readPhotos(json['photos']);
    final photos = decodedPhotos.isNotEmpty
        ? decodedPhotos
        : (legacyPhoto.isEmpty && legacyLocalPhoto.isEmpty
              ? const <CheckInPhotoAsset>[]
              : [
                  CheckInPhotoAsset(
                    photo: legacyPhoto,
                    localPhoto: legacyLocalPhoto,
                  ),
                ]);
    final primary = photos.isEmpty ? null : photos.first;
    return CheckIn(
      id: json['id']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      place: json['place']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      source: json['source']?.toString() ?? 'manual',
      synced: json['synced'] == true || json['synced'] == 'true',
      createdAt:
          (json['createdAt'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      photo: legacyPhoto.isNotEmpty ? legacyPhoto : primary?.photo ?? '',
      localPhoto: legacyLocalPhoto.isNotEmpty
          ? legacyLocalPhoto
          : primary?.localPhoto ?? '',
      album: json['album']?.toString() ?? '',
      photos: photos,
      favorite: json['favorite'] == true || json['favorite'] == 'true',
      rating: _readRating(json['rating']),
      tags: _readTags(rawTags),
    );
  }

  static int _readRating(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return parsed.clamp(0, 5);
  }

  static List<String> _readTags(Object? value) {
    if (value is List) {
      return value
          .map((e) => e.toString())
          .map(_cleanTag)
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }
    if (value is String) {
      return value
          .split(',')
          .map(_cleanTag)
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
    }
    return const [];
  }

  static List<CheckInPhotoAsset> _readPhotos(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map(
          (entry) =>
              CheckInPhotoAsset.fromJson(Map<String, dynamic>.from(entry)),
        )
        .where((entry) => entry.hasPhoto)
        .toList();
  }

  static String _cleanTag(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ');

  Map<String, dynamic> toJson() => {
    'id': id,
    'city': city,
    'place': place,
    'notes': notes,
    'source': source,
    'synced': synced,
    'createdAt': createdAt,
    'lat': lat,
    'lng': lng,
    'photo': photo,
    'localPhoto': localPhoto,
    'album': album,
    'photos': photoItems.map((entry) => entry.toJson()).toList(),
    'favorite': favorite,
    'rating': rating,
    'tags': tags,
  };
}
