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
      favorite: favorite ?? this.favorite,
      rating: rating ?? this.rating,
      tags: tags ?? this.tags,
    );
  }

  bool get hasPhoto => localPhoto.isNotEmpty || photo.isNotEmpty;
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
    favorite: favorite,
    rating: rating,
    tags: tags,
  );

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
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
      photo: json['photo']?.toString() ?? '',
      localPhoto: json['localPhoto']?.toString() ?? '',
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
    'favorite': favorite,
    'rating': rating,
    'tags': tags,
  };
}
