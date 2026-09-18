class AlbumPhoto {
  const AlbumPhoto({
    required this.id,
    this.photo = '',
    this.localPhoto = '',
    this.name = '',
    this.place = '',
    this.note = '',
    this.createdAt = 0,
  });

  final String id;
  final String photo;
  final String localPhoto;
  final String name;
  final String place;
  final String note;
  final int createdAt;

  bool get hasPhoto => photo.isNotEmpty || localPhoto.isNotEmpty;

  AlbumPhoto copyWith({
    String? photo,
    String? localPhoto,
    String? place,
    String? note,
  }) => AlbumPhoto(
    id: id,
    photo: photo ?? this.photo,
    localPhoto: localPhoto ?? this.localPhoto,
    name: name,
    place: place ?? this.place,
    note: note ?? this.note,
    createdAt: createdAt,
  );

  factory AlbumPhoto.fromJson(Map<String, dynamic> json) => AlbumPhoto(
    id: json['id']?.toString() ?? '',
    photo: json['photo']?.toString() ?? '',
    localPhoto: json['localPhoto']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    place: json['place']?.toString() ?? '',
    note: json['note']?.toString() ?? '',
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'photo': photo,
    'localPhoto': localPhoto,
    'name': name,
    'place': place,
    'note': note,
    'createdAt': createdAt,
  };
}

class TravelAlbum {
  const TravelAlbum({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.checkInIds = const [],
    this.photos = const [],
    this.deletedPhotoIds = const [],
    this.excludedCheckInIds = const [],
    this.isDeleted = false,
    this.coverPhotoId = '',
    this.localOnly = false,
  });

  final String id;
  final String name;
  final int createdAt;
  final int updatedAt;
  final List<String> checkInIds;
  final List<AlbumPhoto> photos;
  final List<String> deletedPhotoIds;
  final List<String> excludedCheckInIds;
  final bool isDeleted;
  final String coverPhotoId;
  final bool localOnly;

  TravelAlbum copyWith({
    String? name,
    int? updatedAt,
    List<String>? checkInIds,
    List<AlbumPhoto>? photos,
    List<String>? deletedPhotoIds,
    List<String>? excludedCheckInIds,
    bool? isDeleted,
    String? coverPhotoId,
    bool? localOnly,
  }) => TravelAlbum(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    checkInIds: checkInIds ?? this.checkInIds,
    photos: photos ?? this.photos,
    deletedPhotoIds: deletedPhotoIds ?? this.deletedPhotoIds,
    excludedCheckInIds: excludedCheckInIds ?? this.excludedCheckInIds,
    isDeleted: isDeleted ?? this.isDeleted,
    coverPhotoId: coverPhotoId ?? this.coverPhotoId,
    localOnly: localOnly ?? this.localOnly,
  );

  factory TravelAlbum.fromJson(Map<String, dynamic> json) => TravelAlbum(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    checkInIds:
        (json['checkInIds'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
    photos:
        (json['photos'] as List?)
            ?.whereType<Map>()
            .map(
              (value) => AlbumPhoto.fromJson(Map<String, dynamic>.from(value)),
            )
            .where((photo) => photo.id.isNotEmpty && photo.hasPhoto)
            .toList() ??
        const [],
    deletedPhotoIds:
        (json['deletedPhotoIds'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
    excludedCheckInIds:
        (json['excludedCheckInIds'] as List?)
            ?.map((value) => value.toString())
            .toList() ??
        const [],
    isDeleted: json['isDeleted'] == true,
    coverPhotoId: json['coverPhotoId']?.toString() ?? '',
    localOnly: json['localOnly'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'checkInIds': checkInIds,
    'photos': photos.map((photo) => photo.toJson()).toList(),
    'deletedPhotoIds': deletedPhotoIds,
    'excludedCheckInIds': excludedCheckInIds,
    'isDeleted': isDeleted,
    'coverPhotoId': coverPhotoId,
    'localOnly': localOnly,
  };
}
