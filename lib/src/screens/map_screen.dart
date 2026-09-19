import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/checkin.dart';
import '../repositories/backend_config.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/local_image_storage.dart';
import '../repositories/image_optimizer.dart';
import '../repositories/photo_export.dart';
import '../repositories/privacy_settings.dart';
import '../repositories/sync_service.dart';
import '../repositories/vietnam_regions.dart';
import '../theme/app_colors.dart';
import '../widgets/checkin_photo.dart';
import 'history_screen.dart';

class _PickedPhoto {
  const _PickedPhoto({required this.file, required this.bytes});

  final XFile file;
  final List<int> bytes;
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.checkinOnly = false});

  final bool checkinOnly;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _repo = CheckInRepository();
  final _checkInFormKey = GlobalKey<FormState>();
  final _cityCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _drawerCtrl = DraggableScrollableController();

  List<CheckIn> _items = [];
  int _historyRevision = 0;
  List<_ProvinceShape> _provinces = [];
  Rect? _geoBounds;
  String _sourceFilter = 'all';
  String _photoInfo = 'Temporary photo: web-safe mode';
  String _backendUrl = BackendConfig.defaultUrl;
  List<_PickedPhoto> _pickedPhotos = [];
  DateTime? _takenAt;
  CheckIn? _selected;
  String? _selectedProvince;
  String? _hoverProvince;
  Offset? _hoverPosition;
  Size? _projectedSize;
  List<_ProjectedProvince> _projectedProvinces = [];
  double _latitude = 0;
  double _longitude = 0;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _loadBackendUrl();
    _load();
    _loadGeoJson();
    _recoverLostPhoto();
  }

  Future<void> _recoverLostPhoto() async {
    try {
      final response = await ImagePicker().retrieveLostData();
      if (response.isEmpty) return;
      final recovered = <_PickedPhoto>[];
      for (final file in response.files ?? const <XFile>[]) {
        final optimized = await const ImageOptimizer().optimize(
          await file.readAsBytes(),
          file.name,
        );
        recovered.add(
          _PickedPhoto(
            file: XFile.fromData(optimized.bytes, name: optimized.fileName),
            bytes: optimized.bytes,
          ),
        );
      }
      if (!mounted || recovered.isEmpty) return;
      setState(() {
        _pickedPhotos = [..._pickedPhotos, ...recovered];
        _photoInfo = '${_pickedPhotos.length} recovered photo(s) selected';
      });
    } catch (_) {
      // Lost picker data is optional; the check-in form remains usable.
    }
  }

  Future<void> _loadBackendUrl() async {
    final url = await BackendConfig.loadUrl();
    if (!mounted) return;
    setState(() => _backendUrl = url);
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _placeCtrl.dispose();
    _notesCtrl.dispose();
    _albumCtrl.dispose();
    _searchCtrl.dispose();
    _drawerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGeoJson() async {
    final raw = await rootBundle.loadString('assets/vietnam-provinces.geojson');
    final jsonMap = jsonDecode(raw) as Map<String, dynamic>;
    final features = (jsonMap['features'] as List).cast<Map<String, dynamic>>();
    final provinces = <_ProvinceShape>[];
    double minLng = 180, minLat = 180, maxLng = -180, maxLat = -180;

    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final type = geometry['type']?.toString();
      final coordinates = geometry['coordinates'];
      final name = _provinceName(
        feature['properties'] as Map<String, dynamic>? ?? const {},
      );
      final rings = <List<dynamic>>[];
      if (type == 'Polygon') {
        rings.addAll((coordinates as List).cast<List<dynamic>>());
      } else if (type == 'MultiPolygon') {
        for (final polygon in coordinates as List) {
          rings.addAll((polygon as List).cast<List<dynamic>>());
        }
      }
      for (final ring in rings) {
        final pts = <Offset>[];
        for (final point in ring) {
          final lng = (point[0] as num).toDouble();
          final lat = (point[1] as num).toDouble();
          pts.add(Offset(lng, lat));
          minLng = min(minLng, lng);
          maxLng = max(maxLng, lng);
          minLat = min(minLat, lat);
          maxLat = max(maxLat, lat);
        }
        provinces.add(_ProvinceShape(name: name, ring: pts));
      }
    }

    if (!mounted) return;
    setState(() {
      _provinces = provinces;
      _geoBounds = Rect.fromLTRB(minLng, minLat, maxLng, maxLat);
      _projectedSize = null;
      _projectedProvinces = [];
    });
  }

  String _provinceName(Map<String, dynamic> props) {
    return (props['ten_tinh'] ?? props['Name'] ?? props['name'] ?? '')
        .toString();
  }

  Future<void> _load() async {
    final items = await _repo.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _historyRevision += 1;
    });
  }

  List<CheckIn> get _filteredItems {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((item) {
      final matchesQuery =
          q.isEmpty ||
          item.city.toLowerCase().contains(q) ||
          item.place.toLowerCase().contains(q) ||
          item.notes.toLowerCase().contains(q) ||
          item.tags.any((tag) => tag.toLowerCase().contains(q));
      final matchesSource =
          _sourceFilter == 'all' || item.source == _sourceFilter;
      return matchesQuery && matchesSource;
    }).toList();
  }

  bool get _hasActiveFilters =>
      _searchCtrl.text.trim().isNotEmpty || _sourceFilter != 'all';

  void _clearFilters() {
    _searchCtrl.clear();
    setState(() => _sourceFilter = 'all');
  }

  Future<void> _pickPhoto([ImageSource? source]) async {
    final cameraFile = source == null
        ? null
        : await ImagePicker().pickImage(source: source, imageQuality: 92);
    final files = source == null
        ? await openFiles(
            acceptedTypeGroups: const [
              XTypeGroup(
                label: 'Images',
                extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
                mimeTypes: [
                  'image/jpeg',
                  'image/png',
                  'image/webp',
                  'image/gif',
                ],
              ),
            ],
          )
        : cameraFile == null
        ? <XFile>[]
        : [cameraFile];
    if (files.isEmpty) return;
    final picked = <_PickedPhoto>[];
    for (final file in files) {
      final optimized = await const ImageOptimizer().optimize(
        await file.readAsBytes(),
        file.name,
      );
      picked.add(
        _PickedPhoto(
          file: XFile.fromData(optimized.bytes, name: optimized.fileName),
          bytes: optimized.bytes,
        ),
      );
    }
    setState(() {
      _pickedPhotos = [..._pickedPhotos, ...picked];
      _photoInfo = '${_pickedPhotos.length} new photo(s) selected';
      _takenAt = DateTime.now();
    });
  }

  Future<void> _saveEditedCheckin(CheckIn original) async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) return;
    final checkInAt =
        _takenAt ?? DateTime.fromMillisecondsSinceEpoch(original.createdAt);
    final createdAt = checkInAt.millisecondsSinceEpoch;
    final photos = [...original.photoItems];
    final uploads = <PhotoUpload>[];
    for (var index = 0; index < _pickedPhotos.length; index += 1) {
      final picked = _pickedPhotos[index];
      final localPhoto = await LocalImageStorage.saveImage(
        bytes: picked.bytes,
        originalName: picked.file.name,
        city: city,
        album: _albumCtrl.text.trim(),
        createdAt: createdAt + index,
      );
      photos.add(
        CheckInPhotoAsset(
          localPhoto: localPhoto,
          name: picked.file.name,
          createdAt: createdAt + index,
        ),
      );
      uploads.add(PhotoUpload(bytes: picked.bytes, fileName: picked.file.name));
    }
    final primary = photos.isEmpty ? null : photos.first;
    var updated = CheckIn(
      id: original.id,
      city: city,
      place: _placeCtrl.text.trim().isEmpty ? city : _placeCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      source: original.source,
      synced: false,
      createdAt: createdAt,
      lat: _latitude,
      lng: _longitude,
      photo: primary?.photo ?? '',
      localPhoto: primary?.localPhoto ?? '',
      album: _albumCtrl.text.trim(),
      photos: photos,
      favorite: original.favorite,
      rating: original.rating,
      tags: original.tags,
      localOnly: original.localOnly,
      hideLocation: original.hideLocation,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    try {
      if (updated.localOnly) throw const FormatException('Local-only check-in');
      final sync = SyncService(baseUrl: await BackendConfig.loadUrl());
      final remote = await sync.push(
        updated,
        photoUploads: uploads.isEmpty ? null : uploads,
      );
      updated = sync.mergeLocalPhotos(remote.copyWith(synced: true), updated);
    } catch (_) {
      // Keep the edit locally and let two-way sync retry later.
    }
    await _repo.update(updated);
    if (!mounted) return;
    Navigator.of(context).pop();
    await _load();
    if (!mounted) return;
    _clearCheckInForm();
    _openDetail(updated);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Check-in updated.')));
  }

  void _clearCheckInForm() {
    _cityCtrl.clear();
    _placeCtrl.clear();
    _notesCtrl.clear();
    _albumCtrl.clear();
    _photoInfo = 'No metadata read yet';
    _pickedPhotos = [];
    _takenAt = null;
  }

  Future<void> _selectCheckInDateTime() async {
    final initial = _takenAt ?? DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: 'When did this memory happen?',
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'What time was it?',
    );
    if (!mounted) return;
    setState(() {
      _takenAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? initial.hour,
        pickedTime?.minute ?? initial.minute,
      );
    });
  }

  Future<void> _saveCheckin() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) return;
    final createdAt = (_takenAt ?? DateTime.now()).millisecondsSinceEpoch;
    final photos = <CheckInPhotoAsset>[];
    final uploads = <PhotoUpload>[];
    for (var index = 0; index < _pickedPhotos.length; index += 1) {
      final picked = _pickedPhotos[index];
      final localPhoto = await LocalImageStorage.saveImage(
        bytes: picked.bytes,
        originalName: picked.file.name,
        city: city,
        album: _albumCtrl.text.trim(),
        createdAt: createdAt + index,
      );
      photos.add(
        CheckInPhotoAsset(
          localPhoto: localPhoto,
          name: picked.file.name,
          createdAt: createdAt + index,
        ),
      );
      uploads.add(PhotoUpload(bytes: picked.bytes, fileName: picked.file.name));
    }
    final primary = photos.isEmpty ? null : photos.first;
    final privacy = await PrivacySettings.load();
    final item = CheckIn(
      id: const Uuid().v4(),
      city: city,
      place: _placeCtrl.text.trim().isEmpty ? city : _placeCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      source: 'manual',
      synced: false,
      createdAt: createdAt,
      lat: _latitude,
      lng: _longitude,
      photo: primary?.photo ?? '',
      localPhoto: primary?.localPhoto ?? '',
      album: _albumCtrl.text.trim(),
      photos: photos,
      localOnly: privacy.localOnly,
      hideLocation: privacy.hideLocation,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    final backendUrl = await BackendConfig.loadUrl();
    final sync = SyncService(baseUrl: backendUrl);
    var savedItem = item;
    try {
      if (item.localOnly) throw const FormatException('Local-only check-in');
      savedItem = await sync.push(
        item,
        photoUploads: uploads.isEmpty ? null : uploads,
      );
      savedItem = sync.mergeLocalPhotos(savedItem.copyWith(synced: true), item);
    } catch (_) {
      savedItem = item.copyWith(synced: false);
    }
    await _repo.add(savedItem);
    _clearCheckInForm();
    setState(() {
      _selected = savedItem;
      _selectedProvince = null;
    });
    await _load();
    if (!mounted) return;
    final savedOnline = savedItem.synced;
    // The form is a modal on the MapScreen navigator. Popping the GoRouter
    // root navigator here can remove the entire /map route on mobile.
    Navigator.of(context).pop();
    _openDetail(savedItem);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            savedOnline
                ? 'Check-in saved and synced.'
                : 'Check-in saved locally. It will sync when the backend is available.',
          ),
        ),
      );
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const FormatException('Turn on Location Services first.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const FormatException('Location permission was not granted.');
      }
      final position = await Geolocator.getCurrentPosition();
      if (_provinces.isEmpty) await _loadGeoJson();
      final point = Offset(position.longitude, position.latitude);
      var province = '';
      for (final shape in _provinces) {
        if (_containsPoint(shape.ring, point)) {
          province = shape.name;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        if (province.isNotEmpty) {
          _cityCtrl.text = province;
          if (_placeCtrl.text.trim().isEmpty) _placeCtrl.text = province;
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('FormatException: ', ''),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  bool _containsPoint(List<dynamic> polygon, Offset point) {
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i] as Offset;
      final b = polygon[j] as Offset;
      final crosses =
          (a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  void _openForm([String? city, CheckIn? editing]) {
    final colors = AppColors.of(context);
    _clearCheckInForm();
    if (editing != null) {
      _latitude = editing.lat;
      _longitude = editing.lng;
      _cityCtrl.text = editing.city;
      _placeCtrl.text = editing.place;
      _notesCtrl.text = editing.notes;
      _albumCtrl.text = editing.album;
      _takenAt = DateTime.fromMillisecondsSinceEpoch(editing.createdAt);
      _photoInfo = editing.hasPhoto
          ? '${editing.photoCount} photo(s) in this album'
          : 'No photo';
    } else if (city != null && city.isNotEmpty) {
      _cityCtrl.text = city;
      _placeCtrl.text = city;
      _latitude = 0;
      _longitude = 0;
    } else {
      _latitude = 0;
      _longitude = 0;
    }
    _takenAt ??= DateTime.now();
    var isSaving = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                final checkInAt = _takenAt ?? DateTime.now();
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Form(
                    key: _checkInFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 4,
                            decoration: BoxDecoration(
                              color: colors.line,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    editing == null
                                        ? 'New check-in'
                                        : 'Edit check-in',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Save the place first. Photos and details are optional.',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              tooltip: 'Close check-in form',
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _cityCtrl,
                          autofocus: editing == null && city == null,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Choose or enter a province / city.';
                            }
                            return null;
                          },
                          decoration: const InputDecoration(
                            labelText: 'Province / City',
                            hintText: 'e.g. Lâm Đồng',
                            helperText:
                                'Use a province name for Map and Insights coverage.',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _locating
                              ? null
                              : () async {
                                  await _useCurrentLocation();
                                  setModalState(() {});
                                },
                          icon: _locating
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location_outlined),
                          label: Text(
                            _latitude == 0 && _longitude == 0
                                ? 'Use current location'
                                : '${_latitude.toStringAsFixed(5)}, ${_longitude.toStringAsFixed(5)}',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _placeCtrl,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Place',
                            hintText: 'e.g. Hồ Xuân Hương, Đà Lạt',
                            prefixIcon: Icon(Icons.place_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _selectCheckInDateTime();
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              DateFormat(
                                'EEE, d MMM yyyy · HH:mm',
                              ).format(checkInAt),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          initiallyExpanded: true,
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 4),
                          leading: const Icon(Icons.photo_library_outlined),
                          title: const Text('Photos and details'),
                          subtitle: const Text(
                            'Add photos, notes and travel details',
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await _pickPhoto();
                                      setModalState(() {});
                                    },
                                    icon: const Icon(
                                      Icons.photo_library_outlined,
                                    ),
                                    label: Text('Choose photos'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await _pickPhoto(ImageSource.camera);
                                      setModalState(() {});
                                    },
                                    icon: const Icon(
                                      Icons.photo_camera_outlined,
                                    ),
                                    label: const Text('Take photo'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_pickedPhotos.isNotEmpty)
                              SizedBox(
                                height: 104,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _pickedPhotos.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (context, index) => Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: Image.memory(
                                          Uint8List.fromList(
                                            _pickedPhotos[index].bytes,
                                          ),
                                          width: 104,
                                          height: 104,
                                          fit: BoxFit.cover,
                                          semanticLabel:
                                              'Selected check-in photo ${index + 1}',
                                        ),
                                      ),
                                      Positioned(
                                        top: 2,
                                        right: 2,
                                        child: IconButton.filledTonal(
                                          tooltip:
                                              'Remove selected photo ${index + 1}',
                                          onPressed: () {
                                            setState(() {
                                              _pickedPhotos.removeAt(index);
                                              _photoInfo = _pickedPhotos.isEmpty
                                                  ? ''
                                                  : '${_pickedPhotos.length} new photo(s) selected';
                                            });
                                            setModalState(() {});
                                          },
                                          icon: const Icon(Icons.close),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (editing?.hasPhoto ?? false)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.panel2,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: colors.line),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.photo_outlined),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Current album photos will be kept. Choose more photos to add to it.',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_pickedPhotos.isNotEmpty ||
                                (editing?.hasPhoto ?? false)) ...[
                              const SizedBox(height: 8),
                              Text(
                                _photoInfo,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _notesCtrl,
                              textCapitalization: TextCapitalization.sentences,
                              minLines: 3,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: 'Note',
                                hintText: 'What made this memory special?',
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  if (!(_checkInFormKey.currentState
                                          ?.validate() ??
                                      false)) {
                                    return;
                                  }
                                  FocusScope.of(context).unfocus();
                                  setModalState(() => isSaving = true);
                                  try {
                                    if (editing == null) {
                                      await _saveCheckin();
                                    } else {
                                      await _saveEditedCheckin(editing);
                                    }
                                  } catch (error) {
                                    if (!context.mounted) return;
                                    setModalState(() => isSaving = false);
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Could not save this check-in: $error',
                                          ),
                                        ),
                                      );
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  editing == null
                                      ? Icons.bookmark_add_outlined
                                      : Icons.check_circle_outline,
                                ),
                          label: Text(
                            isSaving
                                ? 'Saving…'
                                : editing == null
                                ? 'Save check-in'
                                : 'Save changes',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Offset _project(double lng, double lat, Size size) {
    final bounds = _geoBounds;
    if (bounds == null) return Offset.zero;
    final paddingX = size.width * 0.04;
    final paddingY = size.height * 0.04;
    final usableW = size.width - paddingX * 2;
    final usableH = size.height - paddingY * 2;
    final normX = (lng - bounds.left) / bounds.width;
    final normY = (lat - bounds.top) / bounds.height;
    final x = paddingX + normX * usableW;
    final y = paddingY + normY * usableH;
    return Offset(x, y);
  }

  Path _provincePath(List<Offset> ring, Size size) {
    final path = Path();
    if (ring.isEmpty) return path;
    final first = _project(ring.first.dx, ring.first.dy, size);
    path.moveTo(first.dx, first.dy);
    for (final p in ring.skip(1)) {
      final mapped = _project(p.dx, p.dy, size);
      path.lineTo(mapped.dx, mapped.dy);
    }
    path.close();
    return path;
  }

  _ProvinceShape? _provinceAt(Offset point, Size size) {
    for (final province in _projectedFor(size).reversed) {
      if (province.path.contains(point)) {
        return province.source;
      }
    }
    return null;
  }

  List<_ProjectedProvince> _projectedFor(Size size) {
    if (_projectedSize == size && _projectedProvinces.isNotEmpty) {
      return _projectedProvinces;
    }
    _projectedSize = size;
    _projectedProvinces = _provinces
        .where((province) => province.ring.length >= 3)
        .map(
          (province) => _ProjectedProvince(
            source: province,
            path: _provincePath(province.ring, size),
          ),
        )
        .toList();
    return _projectedProvinces;
  }

  Map<String, int> _provinceStats() {
    final stats = <String, int>{};
    for (final item in _items) {
      final key = _cleanName(item.city);
      stats[key] = (stats[key] ?? 0) + 1;
    }
    return stats;
  }

  String _cleanName(String value) {
    return VietnamRegions.normalize(value);
  }

  List<CheckIn> _provincePhotos(String provinceName) {
    final clean = _cleanName(provinceName);
    final photos = _items.where((item) {
      final city = _cleanName(item.city);
      return item.hasPhoto &&
          (city == clean || city.contains(clean) || clean.contains(city));
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return photos.take(3).toList();
  }

  String _photoUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_backendUrl/$path';
  }

  void _openDetail(CheckIn item) {
    setState(() {
      _selected = item;
      _selectedProvince = null;
    });
    _drawerCtrl.animateTo(
      0.55,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _deleteSelected() async {
    final item = _selected;
    if (item == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete check-in?'),
        content: Text(
          'Remove ${item.place} from your local travel memories? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete check-in'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final photo in item.photoItems) {
      await LocalImageStorage.deleteImage(photo.localPhoto);
    }
    try {
      await SyncService(
        baseUrl: await BackendConfig.loadUrl(),
      ).deleteCheckIn(item.id);
    } catch (_) {
      // The local delete still succeeds while offline.
    }
    await _repo.remove(item.id);
    await _load();
    setState(() => _selected = null);
  }

  void _openEditCheckin(CheckIn item) => _openForm(null, item);

  Future<void> _deletePhoto() async {
    final item = _selected;
    if (item == null || !item.hasPhoto) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete photo?'),
        content: Text('Remove the photo from ${item.place}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete photo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (item.photoItems.any((photo) => photo.photo.isNotEmpty)) {
        await SyncService(
          baseUrl: await BackendConfig.loadUrl(),
        ).deletePhoto(item.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connect to the backend before deleting synced photos: $error',
            ),
          ),
        );
      }
      return;
    }
    for (final photo in item.photoItems) {
      await LocalImageStorage.deleteImage(photo.localPhoto);
    }
    await _repo.deletePhoto(item.id);
    final updated = item.withoutPhoto();
    await _load();
    if (mounted) setState(() => _selected = updated);
  }

  Future<void> _savePhotoAsset(CheckInPhotoAsset asset) async {
    try {
      final saved = await PhotoExport.save(
        localPhoto: asset.localPhoto,
        remotePhoto: asset.photo,
        baseUrl: await BackendConfig.loadUrl(),
        fileName: asset.name,
      );
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved to your device.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save photo: $error')));
      }
    }
  }

  Future<void> _deletePhotoAsset(CheckIn item, CheckInPhotoAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: Text('Remove this photo from ${item.place}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete photo'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final remaining = item.photoItems.where((photo) => photo != asset).toList();
    final primary = remaining.isEmpty ? null : remaining.first;
    var updated = item.copyWith(
      photo: primary?.photo ?? '',
      localPhoto: primary?.localPhoto ?? '',
      photos: remaining,
      synced: false,
    );
    try {
      if (asset.photo.isNotEmpty) {
        final sync = SyncService(baseUrl: await BackendConfig.loadUrl());
        final remote = await sync.deletePhotoAsset(item.id, asset.photo);
        updated = sync.mergeLocalPhotos(remote.copyWith(synced: true), updated);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Connect to the backend before deleting this photo: $error',
            ),
          ),
        );
      }
      return;
    }
    await LocalImageStorage.deleteImage(asset.localPhoto);
    await _repo.update(updated);
    await _load();
    if (mounted) setState(() => _selected = updated);
  }

  void _openPhotoGallery(CheckIn item) {
    final assets = item.photoItems;
    var currentIndex = 0;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.place,
                          style: Theme.of(dialogContext).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close photos',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: PageView.builder(
                    itemCount: assets.length,
                    onPageChanged: (index) =>
                        setDialogState(() => currentIndex = index),
                    itemBuilder: (context, index) {
                      final asset = assets[index];
                      return InteractiveViewer(
                        child: CheckInPhoto(
                          item: item.copyWith(
                            photo: asset.photo,
                            localPhoto: asset.localPhoto,
                            photos: const [],
                          ),
                          remoteUrl: _photoUrl,
                          fit: BoxFit.contain,
                        ),
                      );
                    },
                  ),
                ),
                if (assets.length > 1)
                  Text('${assets.length} photos · swipe to browse'),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _savePhotoAsset(assets[currentIndex]);
                        },
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Save to device'),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _deletePhotoAsset(item, assets[currentIndex]);
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Delete this photo'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openProvinceDetail(String provinceName) {
    setState(() {
      _selected = null;
      _selectedProvince = provinceName;
    });
    _drawerCtrl.animateTo(
      0.58,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  List<CheckIn> _provinceItems(String provinceName) {
    final clean = _cleanName(provinceName);
    final items = _items.where((item) {
      final city = _cleanName(item.city);
      return city == clean || city.contains(clean) || clean.contains(city);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  List<String> get _provinceNames {
    final names = _provinces.map((province) => province.name).toSet().toList();
    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  Widget _buildFilters() {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.line),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Find check-ins',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_hasActiveFilters)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear_all_outlined),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search check-ins',
              hintText: 'Hanoi, Da Nang, beach...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _sourceFilter,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All')),
              DropdownMenuItem(value: 'gps', child: Text('GPS')),
              DropdownMenuItem(value: 'manual', child: Text('Manual')),
              DropdownMenuItem(value: 'ai', child: Text('AI')),
            ],
            onChanged: (value) =>
                setState(() => _sourceFilter = value ?? 'all'),
            decoration: const InputDecoration(labelText: 'Check-in source'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentList() {
    final colors = AppColors.of(context);
    final filtered = _filteredItems
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final items = filtered;
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.line),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your check-ins',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          Text(
            filtered.isEmpty
                ? 'No check-ins found'
                : '${filtered.length} matching check-in${filtered.length == 1 ? '' : 's'}',
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.panel2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('No matching check-ins yet.'),
                  if (_hasActiveFilters) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear_all_outlined),
                      label: const Text('Clear filters'),
                    ),
                  ],
                ],
              ),
            )
          else
            ...items.map(
              (item) => InkWell(
                onTap: () => _openDetail(item),
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.panel2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colors.line),
                  ),
                  child: Row(
                    children: [
                      _CheckInThumb(item: item, photoUrl: _photoUrl),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.city,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.place,
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _StatusChip(text: item.source.toUpperCase()),
                          const SizedBox(height: 6),
                          Text(
                            DateFormat('dd/MM/yyyy').format(
                              DateTime.fromMillisecondsSinceEpoch(
                                item.createdAt,
                              ),
                            ),
                            style: TextStyle(color: colors.muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    final colors = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x103A2B19),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vietnam map', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Tap a province to view its memories or add a new one. On desktop, hover for recent photos.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (value) {
                final query = VietnamRegions.normalize(value.text);
                if (query.isEmpty) return const Iterable<String>.empty();
                return _provinceNames.where(
                  (name) => VietnamRegions.normalize(name).contains(query),
                );
              },
              onSelected: _openProvinceDetail,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (value) {
                        final query = VietnamRegions.normalize(value);
                        if (query.isEmpty) return;
                        final match = _provinceNames.cast<String?>().firstWhere(
                          (name) =>
                              name != null &&
                              VietnamRegions.normalize(name).contains(query),
                          orElse: () => null,
                        );
                        if (match != null) _openProvinceDetail(match);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Find a province or city',
                        hintText: 'Type Đà Nẵng, Hà Nội...',
                        prefixIcon: Icon(Icons.travel_explore_outlined),
                      ),
                    );
                  },
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 0.78,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.panel2,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: colors.line),
                ),
                child: _geoBounds == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final size = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          final stats = _provinceStats();
                          final projected = _projectedFor(size);
                          final tooltipWidth = min(
                            260.0,
                            max(0.0, size.width - 16),
                          ).toDouble();
                          final maxTooltipLeft = max(
                            8.0,
                            size.width - tooltipWidth - 8,
                          ).toDouble();
                          final maxTooltipTop = max(
                            8.0,
                            size.height - 176,
                          ).toDouble();
                          return Stack(
                            children: [
                              Positioned.fill(
                                child: MouseRegion(
                                  cursor: _hoverProvince == null
                                      ? MouseCursor.defer
                                      : SystemMouseCursors.click,
                                  onExit: (_) => setState(() {
                                    _hoverProvince = null;
                                    _hoverPosition = null;
                                  }),
                                  onHover: (event) {
                                    final hit = _provinceAt(
                                      event.localPosition,
                                      size,
                                    );
                                    final nextName = hit?.name;
                                    if (nextName != _hoverProvince) {
                                      setState(() {
                                        _hoverProvince = nextName;
                                        _hoverPosition = hit == null
                                            ? null
                                            : event.localPosition;
                                      });
                                    }
                                  },
                                  child: Semantics(
                                    label:
                                        'Interactive Vietnam province map. Tap a province to view its memories or add a check-in.',
                                    button: true,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onTapUp: (details) {
                                        final hit = _provinceAt(
                                          details.localPosition,
                                          size,
                                        );
                                        if (hit != null) {
                                          _openProvinceDetail(hit.name);
                                        }
                                      },
                                      child: CustomPaint(
                                        size: size,
                                        painter: _VietnamMapPainter(
                                          provinces: projected,
                                          stats: stats,
                                          hoveredProvince: _hoverProvince,
                                          dark: dark,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 12,
                                right: 12,
                                child: _MapLegend(dark: dark),
                              ),
                              if (_hoverProvince != null &&
                                  _hoverPosition != null)
                                Positioned(
                                  left: (_hoverPosition!.dx + 14)
                                      .clamp(8.0, maxTooltipLeft)
                                      .toDouble(),
                                  top: (_hoverPosition!.dy - 36)
                                      .clamp(8.0, maxTooltipTop)
                                      .toDouble(),
                                  child: SizedBox(
                                    width: tooltipWidth,
                                    child: _ProvinceTip(
                                      name: _hoverProvince!,
                                      count:
                                          stats[_cleanName(_hoverProvince!)] ??
                                          0,
                                      photos: _provincePhotos(_hoverProvince!),
                                      photoUrl: _photoUrl,
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(int total, int provinces, int remaining) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 3 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatCard(width: width, label: 'Total check-ins', value: '$total'),
            _StatCard(
              width: width,
              label: 'Visited provinces',
              value: '$provinces',
            ),
            _StatCard(width: width, label: 'Remaining', value: '$remaining'),
          ],
        );
      },
    );
  }

  Widget _buildDetailDrawer(BuildContext context) {
    final colors = AppColors.of(context);
    final item = _selected;
    final province = _selectedProvince;
    return DraggableScrollableSheet(
      controller: _drawerCtrl,
      initialChildSize: 0.0,
      minChildSize: 0.0,
      maxChildSize: 0.78,
      builder: (context, scrollController) {
        if (item == null && province == null) {
          return const SizedBox.shrink();
        }
        final provinceItems = province == null
            ? <CheckIn>[]
            : _provinceItems(province);
        return Container(
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border.all(color: colors.line),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2D3A2B19),
                blurRadius: 24,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.line,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (province != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            province,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${provinceItems.length} check-in${provinceItems.length == 1 ? '' : 's'} in this province',
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _selectedProvince = null),
                      tooltip: 'Close province details',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _openForm(province),
                  icon: const Icon(Icons.add),
                  label: const Text('Add check-in here'),
                ),
                const SizedBox(height: 12),
                if (provinceItems.isEmpty)
                  _InfoCard(
                    label: 'No check-ins yet',
                    value:
                        'Use the button above to add the first check-in for this province.',
                  )
                else
                  ...provinceItems.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => _openDetail(entry),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.panel2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.line),
                          ),
                          child: Row(
                            children: [
                              _CheckInThumb(item: entry, photoUrl: _photoUrl),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.place,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('dd/MM/yyyy HH:mm').format(
                                        DateTime.fromMillisecondsSinceEpoch(
                                          entry.createdAt,
                                        ),
                                      ),
                                      style: TextStyle(
                                        color: colors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: colors.muted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              if (item != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item.city} · ${item.place}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.source.toUpperCase()} · ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.createdAt))}',
                            style: TextStyle(color: colors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _selected = null),
                      tooltip: 'Close check-in details',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (item.hasPhoto)
                  InkWell(
                    onTap: () => _openPhotoGallery(item),
                    child: Container(
                      height: 220,
                      decoration: BoxDecoration(
                        color: colors.panel2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.line),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: CheckInPhoto(
                        item: item,
                        remoteUrl: _photoUrl,
                        fit: BoxFit.cover,
                        errorText: 'Photo not found locally or on the backend.',
                      ),
                    ),
                  ),
                if (item.hasPhoto)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () => _openPhotoGallery(item),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text('View ${item.photoCount} photo(s)'),
                        ),
                        TextButton.icon(
                          onPressed: _deletePhoto,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete all photos'),
                        ),
                      ],
                    ),
                  ),
                if (!item.hasPhoto)
                  Container(
                    height: 160,
                    decoration: BoxDecoration(
                      color: colors.panel2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.line),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 56,
                    ),
                  ),
                const SizedBox(height: 12),
                if (item.album.isNotEmpty) ...[
                  _InfoCard(label: 'Album / trip', value: item.album),
                  const SizedBox(height: 8),
                ],
                _InfoCard(
                  label: 'Photos',
                  value: item.photoCount == 0
                      ? 'No photos yet'
                      : '${item.photoCount} photo(s)',
                ),
                const SizedBox(height: 8),
                _InfoCard(label: 'Place', value: item.place),
                const SizedBox(height: 8),
                _InfoCard(
                  label: 'Note',
                  value: item.notes.isEmpty ? 'No note yet.' : item.notes,
                ),
                const SizedBox(height: 8),
                _InfoCard(
                  label: 'Status',
                  value: item.synced ? 'Synced' : 'Waiting to sync',
                ),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _openEditCheckin(item),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit check-in'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => context.go('/account'),
                          icon: const Icon(Icons.sync_outlined),
                          label: const Text('Open Account sync'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _deleteSelected,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final total = _items.length;
    final provinces = _items
        .map((item) => VietnamRegions.normalize(item.city))
        .where((name) => name.isNotEmpty)
        .toSet()
        .length;
    final remaining = (63 - provinces).clamp(0, 63);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontal = screenWidth > 1280 ? (screenWidth - 1220) / 2 : 18.0;

    final content = widget.checkinOnly
        ? <Widget>[
            Text('Check-in', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Save places and photos anywhere in Vietnam.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            _buildFilters(),
            const SizedBox(height: 16),
            _buildRecentList(),
          ]
        : <Widget>[
            Text('Map', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            _buildStats(total, provinces, remaining),
            const SizedBox(height: 16),
            if (screenWidth >= 1100)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildMapCard()),
                  const SizedBox(width: 16),
                  Expanded(
                    child: HistoryScreen(
                      key: ValueKey(_historyRevision),
                      embedded: true,
                    ),
                  ),
                ],
              )
            else ...[
              _buildMapCard(),
              const SizedBox(height: 24),
              HistoryScreen(key: ValueKey(_historyRevision), embedded: true),
            ],
          ];

    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.bg, colors.bg2],
            ),
          ),
          child: ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 16),
            children: [...content, const SizedBox(height: 96)],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildDetailDrawer(context),
        ),
        if (widget.checkinOnly &&
            _selected == null &&
            _selectedProvince == null)
          Positioned(
            right: 18,
            bottom: 18,
            child: Semantics(
              label: 'Add a new check-in',
              button: true,
              child: FloatingActionButton.extended(
                heroTag: 'checkin-add',
                onPressed: _openForm,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add check-in'),
                tooltip: 'Add a new check-in',
              ),
            ),
          ),
      ],
    );
  }
}

class _ProvinceShape {
  _ProvinceShape({required this.name, required this.ring});
  final String name;
  final List<Offset> ring;
}

class _ProjectedProvince {
  _ProjectedProvince({required this.source, required this.path});
  final _ProvinceShape source;
  final Path path;
}

class _VietnamMapPainter extends CustomPainter {
  _VietnamMapPainter({
    required this.provinces,
    required this.stats,
    required this.hoveredProvince,
    required this.dark,
  });

  final List<_ProjectedProvince> provinces;
  final Map<String, int> stats;
  final String? hoveredProvince;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = dark ? const Color(0xFFE4E1C8) : const Color(0xFF9B8467)
      ..style = PaintingStyle.stroke
      ..strokeWidth = dark ? 1.2 : 1.1;
    final hoverStroke = Paint()
      ..color = dark ? const Color(0xFFFFF4B8) : const Color(0xFFC47731)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    for (final province in provinces) {
      final count = stats[_legendKey(province.source.name)] ?? 0;
      final isHovered = province.source.name == hoveredProvince;
      final fill = Paint()..color = _fillForCount(count, isHovered);
      canvas.drawPath(province.path, fill);
      canvas.drawPath(province.path, stroke);
      if (isHovered) {
        canvas.drawPath(province.path, hoverStroke);
      }
    }
  }

  Color _fillForCount(int count, bool hovered) {
    if (dark) {
      final base = count == 0
          ? const Color(0xFF596357)
          : count <= 2
          ? const Color(0xFFB7833A)
          : count <= 5
          ? const Color(0xFFD66A2A)
          : const Color(0xFFE93F1D);
      return hovered ? _lighten(base, 0.16) : base;
    }
    final base = count == 0
        ? const Color(0xFFD8D1C2)
        : count <= 2
        ? const Color(0xFFD8B85F)
        : count <= 5
        ? const Color(0xFFD98935)
        : const Color(0xFFC84A24);
    return hovered ? _lighten(base, 0.12) : base;
  }

  String _legendKey(String value) {
    return value
        .toLowerCase()
        .replaceAll('à', 'a')
        .replaceAll('á', 'a')
        .replaceAll('ạ', 'a')
        .replaceAll('ả', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ầ', 'a')
        .replaceAll('ấ', 'a')
        .replaceAll('ậ', 'a')
        .replaceAll('ẩ', 'a')
        .replaceAll('ẫ', 'a')
        .replaceAll('ă', 'a')
        .replaceAll('ằ', 'a')
        .replaceAll('ắ', 'a')
        .replaceAll('ặ', 'a')
        .replaceAll('ẳ', 'a')
        .replaceAll('ẵ', 'a')
        .replaceAll('è', 'e')
        .replaceAll('é', 'e')
        .replaceAll('ẹ', 'e')
        .replaceAll('ẻ', 'e')
        .replaceAll('ẽ', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ề', 'e')
        .replaceAll('ế', 'e')
        .replaceAll('ệ', 'e')
        .replaceAll('ể', 'e')
        .replaceAll('ễ', 'e')
        .replaceAll('ì', 'i')
        .replaceAll('í', 'i')
        .replaceAll('ị', 'i')
        .replaceAll('ỉ', 'i')
        .replaceAll('ĩ', 'i')
        .replaceAll('ò', 'o')
        .replaceAll('ó', 'o')
        .replaceAll('ọ', 'o')
        .replaceAll('ỏ', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ồ', 'o')
        .replaceAll('ố', 'o')
        .replaceAll('ộ', 'o')
        .replaceAll('ổ', 'o')
        .replaceAll('ỗ', 'o')
        .replaceAll('ơ', 'o')
        .replaceAll('ờ', 'o')
        .replaceAll('ớ', 'o')
        .replaceAll('ợ', 'o')
        .replaceAll('ở', 'o')
        .replaceAll('ỡ', 'o')
        .replaceAll('ù', 'u')
        .replaceAll('ú', 'u')
        .replaceAll('ụ', 'u')
        .replaceAll('ủ', 'u')
        .replaceAll('ũ', 'u')
        .replaceAll('ư', 'u')
        .replaceAll('ừ', 'u')
        .replaceAll('ứ', 'u')
        .replaceAll('ự', 'u')
        .replaceAll('ử', 'u')
        .replaceAll('ữ', 'u')
        .replaceAll('ỳ', 'y')
        .replaceAll('ý', 'y')
        .replaceAll('ỵ', 'y')
        .replaceAll('ỷ', 'y')
        .replaceAll('ỹ', 'y')
        .replaceAll('đ', 'd')
        .replaceFirst(RegExp(r'^tp\.?\s*'), '')
        .replaceFirst(RegExp(r'^thanh pho\s+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  Color _lighten(Color color, double amount) {
    return Color.lerp(color, Colors.white, amount) ?? color;
  }

  @override
  bool shouldRepaint(covariant _VietnamMapPainter oldDelegate) {
    return oldDelegate.provinces != provinces ||
        oldDelegate.stats != stats ||
        oldDelegate.hoveredProvince != hoveredProvince ||
        oldDelegate.dark != dark;
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final compact = width < 190;
    return SizedBox(
      width: width,
      height: compact ? 132 : 116,
      child: Container(
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.line),
        ),
        padding: EdgeInsets.all(compact ? 16 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.muted,
                fontSize: compact ? 13 : null,
                height: compact ? 1.25 : null,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: compact ? 6 : 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.accent,
                fontSize: compact ? 24 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.line),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: colors.muted)),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final entries = [
      ('0', dark ? const Color(0xFF596357) : const Color(0xFFD8D1C2)),
      ('1-2', dark ? const Color(0xFFB7833A) : const Color(0xFFD8B85F)),
      ('3-5', dark ? const Color(0xFFD66A2A) : const Color(0xFFD98935)),
      ('6+', dark ? const Color(0xFFE93F1D) : const Color(0xFFC84A24)),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: entries
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: entry.$2,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: colors.text.withValues(alpha: 0.18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.$1,
                        style: TextStyle(
                          color: colors.muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _CheckInThumb extends StatelessWidget {
  const _CheckInThumb({required this.item, required this.photoUrl});

  final CheckIn item;
  final String Function(String path) photoUrl;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: CheckInPhoto(item: item, remoteUrl: photoUrl, emptyIconSize: 20),
    );
  }
}

class _ProvinceTip extends StatelessWidget {
  const _ProvinceTip({
    required this.name,
    required this.count,
    required this.photos,
    required this.photoUrl,
  });

  final String name;
  final int count;
  final List<CheckIn> photos;
  final String Function(String path) photoUrl;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.panel.withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F392B19),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              photos.isEmpty
                  ? 'No photos yet'
                  : '${photos.length} recent photo${photos.length == 1 ? '' : 's'}',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            if (photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: photos
                    .map(
                      (item) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: CheckInPhoto(
                                item: item,
                                remoteUrl: photoUrl,
                                emptyIconSize: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Text(
                DateFormat('dd/MM/yyyy').format(
                  DateTime.fromMillisecondsSinceEpoch(photos.first.createdAt),
                ),
                style: TextStyle(color: colors.muted, fontSize: 11),
              ),
            ] else if (count > 0) ...[
              const SizedBox(height: 6),
              Text(
                '$count check-in',
                style: TextStyle(color: colors.muted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: colors.muted, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
