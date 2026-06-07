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
    );
  }

  bool get hasPhoto => localPhoto.isNotEmpty || photo.isNotEmpty;

  factory CheckIn.fromJson(Map<String, dynamic> json) {
    return CheckIn(
      id: json['id']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      place: json['place']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      source: json['source']?.toString() ?? 'manual',
      synced: json['synced'] == true,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      lat: (json['lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] as num?)?.toDouble() ?? 0,
      photo: json['photo']?.toString() ?? '',
      localPhoto: json['localPhoto']?.toString() ?? '',
    );
  }

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
      };
}
