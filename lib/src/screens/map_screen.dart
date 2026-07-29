import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:image_picker/image_picker.dart' show ImagePicker, ImageSource;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/checkin.dart';
import '../app.dart';
import '../repositories/backend_config.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/local_image_storage.dart';
import '../repositories/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/checkin_photo.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _repo = CheckInRepository();
  final _cityCtrl = TextEditingController();
  final _placeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _drawerCtrl = DraggableScrollableController();

  List<CheckIn> _items = [];
  List<_ProvinceShape> _provinces = [];
  Rect? _geoBounds;
  String _sourceFilter = 'all';
  String _photoInfo = 'Temporary photo: web-safe mode';
  String _backendUrl = BackendConfig.defaultUrl;
  XFile? _pickedPhoto;
  List<int>? _pickedPhotoBytes;
  double? _lat;
  double? _lng;
  DateTime? _takenAt;
  CheckIn? _selected;
  String? _selectedProvince;
  String? _hoverProvince;
  Offset? _hoverPosition;
  Size? _projectedSize;
  List<_ProjectedProvince> _projectedProvinces = [];

  @override
  void initState() {
    super.initState();
    _loadBackendUrl();
    _load();
    _loadGeoJson();
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
    });
  }

  List<CheckIn> get _filteredItems {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _items.where((item) {
      final matchesQuery =
          q.isEmpty ||
          item.city.toLowerCase().contains(q) ||
          item.place.toLowerCase().contains(q) ||
          item.notes.toLowerCase().contains(q);
      final matchesSource =
          _sourceFilter == 'all' || item.source == _sourceFilter;
      return matchesQuery && matchesSource;
    }).toList();
  }

  Future<void> _pickPhoto([ImageSource? source]) async {
    final file = source == null
        ? await openFile(
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
        : await ImagePicker().pickImage(source: source, imageQuality: 92);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedPhoto = file;
      _pickedPhotoBytes = bytes;
      _photoInfo =
          '${file.name} · ${(bytes.length / 1024).toStringAsFixed(1)} KB';
      _takenAt = DateTime.now();
    });
  }

  Future<void> _saveEditedCheckin(CheckIn original) async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) return;
    var localPhoto = original.localPhoto;
    if (_pickedPhotoBytes != null) {
      localPhoto = await LocalImageStorage.saveImage(
        bytes: _pickedPhotoBytes!,
        originalName: _pickedPhoto?.name ?? 'checkin-photo.jpg',
        city: city,
        createdAt: original.createdAt,
      );
      await LocalImageStorage.deleteImage(original.localPhoto);
    }
    var updated = CheckIn(
      id: original.id,
      city: city,
      place: _placeCtrl.text.trim().isEmpty ? city : _placeCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      source: original.source,
      synced: false,
      createdAt: original.createdAt,
      lat: original.lat,
      lng: original.lng,
      photo: original.photo,
      localPhoto: localPhoto,
    );
    try {
      final sync = SyncService(baseUrl: await BackendConfig.loadUrl());
      final remote = await sync.push(
        updated,
        photoBytes: _pickedPhotoBytes,
        photoFileName: _pickedPhoto?.name,
      );
      updated = remote.copyWith(localPhoto: localPhoto, synced: true);
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
    _photoInfo = 'No metadata read yet';
    _pickedPhoto = null;
    _pickedPhotoBytes = null;
    _lat = null;
    _lng = null;
    _takenAt = null;
  }

  Future<void> _saveCheckin() async {
    final city = _cityCtrl.text.trim();
    if (city.isEmpty) return;
    final createdAt = (_takenAt ?? DateTime.now()).millisecondsSinceEpoch;
    final localPhoto = await LocalImageStorage.saveImage(
      bytes: _pickedPhotoBytes ?? const [],
      originalName: _pickedPhoto?.name ?? 'checkin-photo.jpg',
      city: city,
      createdAt: createdAt,
    );
    final item = CheckIn(
      id: const Uuid().v4(),
      city: city,
      place: _placeCtrl.text.trim().isEmpty ? city : _placeCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      source: _lat != null && _lng != null ? 'gps' : 'manual',
      synced: false,
      createdAt: createdAt,
      lat: _lat ?? 21.0285,
      lng: _lng ?? 105.8542,
      photo: '',
      localPhoto: localPhoto,
    );
    final backendUrl = await BackendConfig.loadUrl();
    final sync = SyncService(baseUrl: backendUrl);
    var savedItem = item;
    try {
      savedItem = await sync.push(
        item,
        photoBytes: _pickedPhotoBytes,
        photoFileName: _pickedPhoto?.name,
      );
      savedItem = savedItem.copyWith(synced: true, localPhoto: localPhoto);
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
    VietNamMapApp.navigatorKey.currentState?.pop();
    _openDetail(savedItem);
  }

  void _openForm([String? city, CheckIn? editing]) {
    final colors = AppColors.of(context);
    _clearCheckInForm();
    if (editing != null) {
      _cityCtrl.text = editing.city;
      _placeCtrl.text = editing.place;
      _notesCtrl.text = editing.notes;
      _photoInfo = editing.hasPhoto ? 'Current photo attached' : 'No photo';
    } else if (city != null && city.isNotEmpty) {
      _cityCtrl.text = city;
      _placeCtrl.text = city;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      editing == null ? 'New check-in' : 'Edit check-in',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _pickPhoto();
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            editing == null ? 'Choose photo' : 'Change photo',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _pickPhoto(ImageSource.camera);
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('Take photo'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _photoInfo,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _cityCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Province / City',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _placeCtrl,
                      decoration: const InputDecoration(labelText: 'Place'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: editing == null
                          ? _saveCheckin
                          : () => _saveEditedCheckin(editing),
                      child: Text(editing == null ? 'Save check-in' : 'Update'),
                    ),
                  ],
                ),
              );
            },
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
    return _stripVietnameseMarks(value)
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^tp\.?\s*'), '')
        .replaceFirst(RegExp(r'^thanh pho\s+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String _stripVietnameseMarks(String value) {
    const from =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ'
        'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const to =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd'
        'AAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    var result = value;
    for (var i = 0; i < from.length; i += 1) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result;
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
    await LocalImageStorage.deleteImage(item.localPhoto);
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
    await LocalImageStorage.deleteImage(item.localPhoto);
    try {
      await SyncService(
        baseUrl: await BackendConfig.loadUrl(),
      ).deletePhoto(item.id);
    } catch (_) {
      // Preserve the local deletion and retry on a later sync.
    }
    await _repo.deletePhoto(item.id);
    final updated = item.withoutPhoto();
    await _load();
    if (mounted) setState(() => _selected = updated);
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

  Future<void> _markSynced() async {
    final item = _selected;
    if (item == null) return;
    await _repo.markSynced(item.id);
    await _load();
    setState(() {
      _selected = item.copyWith(synced: true);
    });
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
          Text('Filters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Search',
              hintText: 'Hanoi, Da Nang...',
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
            decoration: const InputDecoration(labelText: 'Source'),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text('New Check-in'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentList() {
    final colors = AppColors.of(context);
    final items = _filteredItems.take(8).toList();
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent check-ins',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                '${items.length} items',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text('No matching data.'),
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
              'Click a province to check in. Hover a province to see recent check-in photos.',
              style: Theme.of(context).textTheme.bodyMedium,
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
                              Positioned(
                                top: 12,
                                left: 12,
                                child: _StatusChip(
                                  text: 'Click a province to check in',
                                  icon: Icons.touch_app,
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
                                  left: (_hoverPosition!.dx + 14).clamp(
                                    8,
                                    size.width - 270,
                                  ),
                                  top: (_hoverPosition!.dy - 36).clamp(
                                    8,
                                    size.height - 176,
                                  ),
                                  child: _ProvinceTip(
                                    name: _hoverProvince!,
                                    count:
                                        stats[_cleanName(_hoverProvince!)] ?? 0,
                                    photos: _provincePhotos(_hoverProvince!),
                                    photoUrl: _photoUrl,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: _openForm,
                  icon: const Icon(Icons.add),
                  label: const Text('Check-in'),
                ),
              ],
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
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (item.hasPhoto)
                  Container(
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
                if (item.hasPhoto)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _deletePhoto,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete photo'),
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
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: () => _openEditCheckin(item),
                        child: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _markSynced,
                      child: const Text('Sync status'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _deleteSelected,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                      ),
                      child: const Text('Delete'),
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
    final provinces = _items.map((e) => e.city).toSet().length;
    final remaining = (63 - provinces).clamp(0, 63);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 1100;
    final horizontal = screenWidth > 1280 ? (screenWidth - 1220) / 2 : 18.0;

    final content = Column(
      children: [
        _buildStats(total, provinces, remaining),
        const SizedBox(height: 16),
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 155, child: _buildMapCard()),
              const SizedBox(width: 16),
              Expanded(
                flex: 85,
                child: Column(
                  children: [
                    _buildFilters(),
                    const SizedBox(height: 16),
                    _buildRecentList(),
                  ],
                ),
              ),
            ],
          )
        else
          Column(
            children: [
              _buildMapCard(),
              const SizedBox(height: 16),
              _buildFilters(),
              const SizedBox(height: 16),
              _buildRecentList(),
            ],
          ),
      ],
    );

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
            children: [content, const SizedBox(height: 96)],
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildDetailDrawer(context),
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
    return SizedBox(
      width: width,
      height: 116,
      child: Container(
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.line),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, this.icon});
  final String text;
  final IconData? icon;

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.muted),
            const SizedBox(width: 6),
          ],
          Text(text, style: TextStyle(fontSize: 12, color: colors.muted)),
        ],
      ),
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
        width: 260,
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
