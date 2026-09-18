import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart'
    show ImagePicker, ImageSource, XFile;
import 'package:uuid/uuid.dart';

import '../models/checkin.dart';
import '../models/travel_album.dart';
import '../repositories/album_repository.dart';
import '../repositories/album_share_service.dart';
import '../repositories/backend_config.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/local_image_storage.dart';
import '../repositories/image_optimizer.dart';
import '../repositories/photo_export.dart';
import '../repositories/privacy_settings.dart';
import '../theme/app_colors.dart';
import '../widgets/checkin_photo.dart';

class AlbumScreen extends StatefulWidget {
  const AlbumScreen({
    super.key,
    this.pickPhotos,
    this.savePhoto,
    this.copyCheckinPhoto,
  });

  final Future<List<XFile>> Function(ImageSource source)? pickPhotos;
  final Future<String> Function(
    XFile file,
    String albumName,
    String place,
    int createdAt,
  )?
  savePhoto;
  final Future<String> Function(
    CheckInPhotoAsset photo,
    CheckIn checkin,
    String albumName,
    int createdAt,
  )?
  copyCheckinPhoto;

  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  final _albums = AlbumRepository();
  final _checkins = CheckInRepository();
  List<TravelAlbum> _savedAlbums = [];
  List<CheckIn> _items = [];
  String _backendUrl = BackendConfig.defaultUrl;
  final _filterCtrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final albums = await _albums.load();
      final items = await _checkins.load();
      final url = await BackendConfig.loadUrl();
      if (!mounted) return;
      setState(() {
        _savedAlbums = albums;
        _items = items;
        _backendUrl = url;
      });
    } catch (error) {
      _message('Could not open albums: $error');
    }
  }

  List<TravelAlbum> get _visibleAlbums {
    final result = _savedAlbums.where((album) => !album.isDeleted).toList();
    final names = result.map((album) => album.name.toLowerCase()).toSet();
    final hiddenLegacyNames = _savedAlbums
        .where((album) => album.isDeleted)
        .map((album) => album.name.toLowerCase())
        .toSet();
    for (final item in _items) {
      final name = item.album.trim();
      if (name.isEmpty ||
          hiddenLegacyNames.contains(name.toLowerCase()) ||
          !names.add(name.toLowerCase())) {
        continue;
      }
      result.add(
        TravelAlbum(
          id: 'legacy:${base64UrlEncode(utf8.encode(name))}',
          name: name,
          createdAt: item.createdAt,
          updatedAt: item.createdAt,
        ),
      );
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (_filter.isEmpty) return result;
    return result.where((album) {
      final linked = _linkedCheckins(album);
      final date = DateTime.fromMillisecondsSinceEpoch(
        album.createdAt,
      ).toIso8601String();
      return album.name.toLowerCase().contains(_filter) ||
          date.contains(_filter) ||
          linked.any(
            (item) =>
                '${item.city} ${item.place}'.toLowerCase().contains(_filter),
          );
    }).toList();
  }

  List<CheckIn> _linkedCheckins(TravelAlbum album) => _items
      .where(
        (item) =>
            !album.excludedCheckInIds.contains(item.id) &&
            (album.checkInIds.contains(item.id) ||
                (item.album.isNotEmpty &&
                    item.album.trim().toLowerCase() ==
                        album.name.toLowerCase())),
      )
      .toList();

  TravelAlbum _materialize(TravelAlbum album) {
    if (!album.id.startsWith('legacy:')) return album;
    return TravelAlbum(
      id: const Uuid().v4(),
      name: album.name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _createAlbum() async {
    var enteredName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New album'),
        content: TextField(
          autofocus: true,
          maxLength: 120,
          textCapitalization: TextCapitalization.words,
          onChanged: (value) => enteredName = value,
          decoration: const InputDecoration(
            labelText: 'Album name',
            hintText: 'Đà Lạt, Miền Tây…',
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(enteredName),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final cleanName = name.trim();
    if (_visibleAlbums.any(
      (album) => album.name.toLowerCase() == cleanName.toLowerCase(),
    )) {
      _message('An album with this name already exists.');
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final privacy = await PrivacySettings.load();
    await _albums.upsert(
      TravelAlbum(
        id: const Uuid().v4(),
        name: cleanName,
        createdAt: now,
        updatedAt: now,
        localOnly: privacy.localOnly,
      ),
    );
    await _load();
    _message('Album created. Add photos or check-ins whenever you like.');
  }

  Future<void> _deleteAlbum(TravelAlbum visible) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${visible.name}?'),
        content: const Text(
          'The album and its own photos will be deleted after Sync. Original check-ins and their photos will stay saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete album'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final album = _materialize(visible);
    await _albums.upsert(
      album.copyWith(
        isDeleted: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        checkInIds: [],
        photos: [],
      ),
    );
    for (final photo in album.photos) {
      await LocalImageStorage.deleteImage(photo.localPhoto);
    }
    await _load();
    _message('Album deleted. Sync from Account to update your other devices.');
  }

  Future<void> _renameAlbum(TravelAlbum visible) async {
    final controller = TextEditingController(text: visible.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename album'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final album = _materialize(visible);
    await _albums.upsert(
      album.copyWith(
        name: name,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _load();
  }

  Future<void> _shareAlbum(TravelAlbum visible) async {
    try {
      final album = _materialize(visible);
      await const AlbumShareService().share(
        album: album,
        linkedCheckIns: _linkedCheckins(visible),
        baseUrl: _backendUrl,
      );
    } catch (error) {
      _message('Could not share album: $error');
    }
  }

  Future<void> _setCover(TravelAlbum visible, String photoId) async {
    final album = _materialize(visible);
    await _albums.upsert(
      album.copyWith(
        coverPhotoId: photoId,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _load();
  }

  Future<void> _movePhoto(
    TravelAlbum visible,
    String photoId,
    int delta,
  ) async {
    final album = _materialize(visible);
    final photos = [...album.photos];
    final index = photos.indexWhere((photo) => photo.id == photoId);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= photos.length) return;
    final moved = photos.removeAt(index);
    photos.insert(target, moved);
    await _albums.upsert(
      album.copyWith(
        photos: photos,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _load();
  }

  Future<void> _addMoment(TravelAlbum visible, ImageSource source) async {
    try {
      final List<XFile> picked;
      if (widget.pickPhotos != null) {
        picked = await widget.pickPhotos!(source);
      } else if (source == ImageSource.camera) {
        final photo = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
        );
        picked = photo == null ? [] : [photo];
      } else {
        picked = await ImagePicker().pickMultiImage(imageQuality: 90);
      }
      if (picked.isEmpty || !mounted) return;
      final selected = [...picked];
      var place = '';
      var note = '';
      final accepted = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) => SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.viewInsetsOf(sheetContext).bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add to ${visible.name}',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${selected.length} photo(s) selected. Add a place and note for this moment.',
                    ),
                    const SizedBox(height: 8),
                    for (var index = 0; index < selected.length; index++)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.photo_outlined),
                        title: Text(
                          selected[index].name.isEmpty
                              ? 'Photo ${index + 1}'
                              : selected[index].name,
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove selected photo ${index + 1}',
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              setSheetState(() => selected.removeAt(index)),
                        ),
                      ),
                    const SizedBox(height: 18),
                    TextField(
                      maxLength: 160,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Place',
                        hintText: 'e.g. Hồ Xuân Hương',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                      onChanged: (value) => place = value,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      maxLength: 2000,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        hintText: 'What made this moment special?',
                      ),
                      onChanged: (value) => note = value,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: selected.isEmpty
                          ? null
                          : () => Navigator.of(sheetContext).pop(true),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save to album'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      if (accepted != true) return;
      var album = _materialize(visible);
      final photos = [...album.photos];
      for (final file in selected) {
        final originalBytes = await file.readAsBytes();
        final optimized = widget.savePhoto == null
            ? await const ImageOptimizer().optimize(originalBytes, file.name)
            : OptimizedImage(bytes: originalBytes, fileName: file.name);
        final bytes = optimized.bytes;
        final createdAt = DateTime.now().millisecondsSinceEpoch;
        final localPhoto = widget.savePhoto != null
            ? await widget.savePhoto!(file, album.name, place.trim(), createdAt)
            : await LocalImageStorage.saveImage(
                bytes: bytes,
                originalName: optimized.fileName,
                city: place.trim().isEmpty ? 'Album' : place.trim(),
                album: album.name,
                createdAt: createdAt,
              );
        photos.add(
          AlbumPhoto(
            id: const Uuid().v4(),
            localPhoto: localPhoto,
            name: optimized.fileName,
            place: place.trim(),
            note: note.trim(),
            createdAt: createdAt,
          ),
        );
      }
      album = album.copyWith(
        photos: photos,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _albums.upsert(album);
      await _load();
      _message(
        '${selected.length} photo(s) saved. Sync from Account to back them up.',
      );
    } catch (error) {
      _message('Could not save this moment: $error');
    }
  }

  Future<void> _addCheckins(TravelAlbum visible) async {
    final linked = _linkedCheckins(visible).map((item) => item.id).toSet();
    final available = _items
        .where((item) => !linked.contains(item.id))
        .toList();
    if (available.isEmpty) {
      _message('No other check-ins are available to add.');
      return;
    }
    final selected = <String>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Add existing check-ins'),
          content: SizedBox(
            width: 480,
            height: 380,
            child: ListView.builder(
              itemCount: available.length,
              itemBuilder: (context, index) {
                final item = available[index];
                return CheckboxListTile(
                  value: selected.contains(item.id),
                  title: Text(item.place),
                  subtitle: Text(item.city),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) {
                      selected.add(item.id);
                    } else {
                      selected.remove(item.id);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || selected.isEmpty) return;
    final album = _materialize(visible);
    await _albums.upsert(
      album.copyWith(
        checkInIds: {...album.checkInIds, ...selected}.toList(),
        excludedCheckInIds: album.excludedCheckInIds
            .where((id) => !selected.contains(id))
            .toList(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _load();
    _message('${selected.length} check-in(s) added to ${album.name}.');
  }

  Future<void> _addPhotosFromCheckins(TravelAlbum visible) async {
    final choices = [
      for (final item in _items)
        for (final photo in item.photoItems)
          _CheckinPhotoChoice(item: item, photo: photo),
    ];
    if (choices.isEmpty) {
      _message('No check-in photos are available yet.');
      return;
    }
    final selected = <int>{};
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Choose check-in photos'),
          content: SizedBox(
            width: 520,
            height: 400,
            child: ListView.builder(
              itemCount: choices.length,
              itemBuilder: (context, index) {
                final choice = choices[index];
                return CheckboxListTile(
                  value: selected.contains(index),
                  secondary: SizedBox(
                    width: 56,
                    height: 56,
                    child: CheckInPhoto(
                      item: _asPhotoItem(
                        choice.photo.photo,
                        choice.photo.localPhoto,
                      ),
                      remoteUrl: _photoUrl,
                    ),
                  ),
                  title: Text(choice.item.place),
                  subtitle: Text(choice.item.city),
                  onChanged: (checked) => setDialogState(() {
                    if (checked == true) {
                      selected.add(index);
                    } else {
                      selected.remove(index);
                    }
                  }),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: const Text('Add photos'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true || selected.isEmpty) return;
    try {
      final album = _materialize(visible);
      final photos = [...album.photos];
      for (final index in selected.toList()..sort()) {
        final choice = choices[index];
        final now = DateTime.now().millisecondsSinceEpoch;
        final name = choice.photo.name.isEmpty
            ? 'checkin-$now.jpg'
            : choice.photo.name;
        final String localPhoto;
        if (widget.copyCheckinPhoto != null) {
          localPhoto = await widget.copyCheckinPhoto!(
            choice.photo,
            choice.item,
            album.name,
            now,
          );
        } else {
          final bytes = await PhotoExport.readBytes(
            localPhoto: choice.photo.localPhoto,
            remotePhoto: choice.photo.photo,
            baseUrl: _backendUrl,
          );
          if (bytes == null || bytes.isEmpty) {
            throw StateError('A selected check-in photo is unavailable.');
          }
          localPhoto = await LocalImageStorage.saveImage(
            bytes: bytes,
            originalName: name,
            city: choice.item.place,
            album: album.name,
            createdAt: now,
          );
        }
        photos.add(
          AlbumPhoto(
            id: const Uuid().v4(),
            localPhoto: localPhoto,
            name: name,
            place: choice.item.place,
            note: choice.item.notes,
            createdAt: now,
          ),
        );
      }
      await _albums.upsert(
        album.copyWith(
          photos: photos,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await _load();
      _message('${selected.length} photo(s) copied to ${album.name}.');
    } catch (error) {
      _message('Could not add check-in photos: $error');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _photoUrl(String path) =>
      path.startsWith('http://') || path.startsWith('https://')
      ? path
      : '$_backendUrl/$path';

  CheckIn _asPhotoItem(String photo, String localPhoto) => CheckIn(
    id: '',
    city: '',
    place: '',
    notes: '',
    source: 'album',
    synced: photo.isNotEmpty,
    createdAt: 0,
    lat: 0,
    lng: 0,
    photo: photo,
    localPhoto: localPhoto,
  );

  Future<void> _savePhoto(_AlbumDisplayPhoto asset) async {
    try {
      final saved = await PhotoExport.save(
        localPhoto: asset.localPhoto,
        remotePhoto: asset.photo,
        baseUrl: _backendUrl,
        fileName: asset.fileName,
      );
      if (saved) _message('Photo saved to your device.');
    } catch (error) {
      _message('Could not save photo: $error');
    }
  }

  Future<void> _removePhotoFromAlbum(
    TravelAlbum visible,
    _AlbumDisplayPhoto asset,
  ) async {
    final owned = asset.albumPhotoId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(owned ? 'Delete this album photo?' : 'Remove from album?'),
        content: Text(
          owned
              ? 'This photo will leave the album and be removed from the backend after Sync.'
              : 'This check-in and its photos will leave the album. The original check-in stays saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(owned ? 'Delete photo' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final album = _materialize(visible);
    if (owned) {
      await _albums.upsert(
        album.copyWith(
          photos: album.photos
              .where((photo) => photo.id != asset.albumPhotoId)
              .toList(),
          deletedPhotoIds: {
            ...album.deletedPhotoIds,
            asset.albumPhotoId!,
          }.toList(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      await LocalImageStorage.deleteImage(asset.localPhoto);
    } else {
      await _albums.upsert(
        album.copyWith(
          checkInIds: album.checkInIds
              .where((id) => id != asset.checkInId)
              .toList(),
          excludedCheckInIds: {
            ...album.excludedCheckInIds,
            asset.checkInId!,
          }.toList(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    await _load();
    _message(
      owned ? 'Photo removed from album.' : 'Check-in removed from album.',
    );
  }

  void _openPhoto(TravelAlbum album, _AlbumDisplayPhoto asset) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
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
                        asset.caption,
                        style: Theme.of(dialogContext).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close photo',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: SizedBox(
                    width: 800,
                    height: 600,
                    child: CheckInPhoto(
                      item: _asPhotoItem(asset.photo, asset.localPhoto),
                      remoteUrl: _photoUrl,
                      fit: BoxFit.contain,
                      errorText: 'Photo is unavailable on this device.',
                    ),
                  ),
                ),
              ),
              if (asset.note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 100),
                    child: SingleChildScrollView(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(asset.note),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _savePhoto(asset);
                      },
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Save to device'),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                        _removePhotoFromAlbum(album, asset);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Text(
                        asset.albumPhotoId == null
                            ? 'Remove from album'
                            : 'Delete photo',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_AlbumDisplayPhoto> _displayPhotos(
    TravelAlbum album,
    List<CheckIn> linked,
  ) {
    final ownPhotos = [...album.photos];
    final coverIndex = ownPhotos.indexWhere(
      (photo) => photo.id == album.coverPhotoId,
    );
    if (coverIndex > 0) ownPhotos.insert(0, ownPhotos.removeAt(coverIndex));
    return [
      for (final photo in ownPhotos)
        _AlbumDisplayPhoto(
          photo: photo.photo,
          localPhoto: photo.localPhoto,
          caption: photo.place.isEmpty
              ? (photo.name.isEmpty ? album.name : photo.name)
              : photo.place,
          note: photo.note,
          fileName: photo.name,
          albumPhotoId: photo.id,
        ),
      for (final item in linked)
        for (final photo in item.photoItems)
          _AlbumDisplayPhoto(
            photo: photo.photo,
            localPhoto: photo.localPhoto,
            caption: item.place,
            note: item.notes,
            fileName: photo.name,
            checkInId: item.id,
          ),
    ];
  }

  Widget _albumCard(TravelAlbum album, AppColors colors) {
    final linked = _linkedCheckins(album);
    final photos = _displayPhotos(album, linked);
    return Card(
      color: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.line),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: colors.panel2,
          foregroundColor: colors.accent,
          child: const Icon(Icons.photo_album_outlined),
        ),
        title: Text(album.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${photos.length} photos · ${linked.length} check-ins'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              tooltip: 'Album actions',
              onSelected: (value) {
                if (value == 'rename') _renameAlbum(album);
                if (value == 'share') _shareAlbum(album);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'share', child: Text('Share ZIP')),
              ],
            ),
            IconButton(
              tooltip: 'Delete album ${album.name}',
              onPressed: () => _deleteAlbum(album),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _addMoment(album, ImageSource.gallery),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add photos'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _addMoment(album, ImageSource.camera),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Take photo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _addCheckins(album),
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Add check-ins'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _addPhotosFromCheckins(album),
                      icon: const Icon(Icons.collections_outlined),
                      label: const Text('From Checkin'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (photos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Center(
                      child: Text(
                        'This album is empty. Add photos or existing check-ins.',
                        style: TextStyle(color: colors.muted),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 700
                          ? 4
                          : constraints.maxWidth >= 440
                          ? 3
                          : 2;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: photos.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (context, index) {
                          final asset = photos[index];
                          return InkWell(
                            onTap: () => _openPhoto(album, asset),
                            borderRadius: BorderRadius.circular(12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: colors.panel2,
                                    child: CheckInPhoto(
                                      item: _asPhotoItem(
                                        asset.photo,
                                        asset.localPhoto,
                                      ),
                                      remoteUrl: _photoUrl,
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      color: Colors.black54,
                                      child: Text(
                                        asset.caption,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (asset.albumPhotoId != null)
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: Row(
                                        children: [
                                          IconButton.filledTonal(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: 'Move photo earlier',
                                            onPressed: () => _movePhoto(
                                              album,
                                              asset.albumPhotoId!,
                                              -1,
                                            ),
                                            icon: const Icon(
                                              Icons.arrow_back,
                                              size: 18,
                                            ),
                                          ),
                                          IconButton.filledTonal(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: 'Set album cover',
                                            onPressed: () => _setCover(
                                              album,
                                              asset.albumPhotoId!,
                                            ),
                                            icon: Icon(
                                              album.coverPhotoId ==
                                                      asset.albumPhotoId
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              size: 18,
                                            ),
                                          ),
                                          IconButton.filledTonal(
                                            visualDensity:
                                                VisualDensity.compact,
                                            tooltip: 'Move photo later',
                                            onPressed: () => _movePhoto(
                                              album,
                                              asset.albumPhotoId!,
                                              1,
                                            ),
                                            icon: const Icon(
                                              Icons.arrow_forward,
                                              size: 18,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                if (linked.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Check-ins',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final item in linked)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(item.place),
                      subtitle: Text(item.city),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final visible = _visibleAlbums;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.bg, colors.bg2],
        ),
      ),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width > 960
              ? (MediaQuery.sizeOf(context).width - 900) / 2
              : 18,
          24,
          MediaQuery.sizeOf(context).width > 960
              ? (MediaQuery.sizeOf(context).width - 900) / 2
              : 18,
          32,
        ),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Albums',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Collect photos and check-ins into your own trips.',
                    style: TextStyle(color: colors.muted),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: _createAlbum,
                icon: const Icon(Icons.add),
                label: const Text('New album'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _filterCtrl,
            onChanged: (value) =>
                setState(() => _filter = value.trim().toLowerCase()),
            decoration: InputDecoration(
              labelText: 'Filter albums by name, place or date',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _filter.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear filter',
                      onPressed: () {
                        _filterCtrl.clear();
                        setState(() => _filter = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          if (visible.isEmpty)
            Card(
              color: colors.panel,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 48,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.photo_library_outlined,
                      size: 48,
                      color: colors.accent,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No albums yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create an album for a trip, then add photos or past check-ins.',
                      style: TextStyle(color: colors.muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            for (final album in visible) _albumCard(album, colors),
        ],
      ),
    );
  }
}

class _AlbumDisplayPhoto {
  const _AlbumDisplayPhoto({
    required this.photo,
    required this.localPhoto,
    required this.caption,
    required this.fileName,
    this.note = '',
    this.albumPhotoId,
    this.checkInId,
  });
  final String photo;
  final String localPhoto;
  final String caption;
  final String fileName;
  final String note;
  final String? albumPhotoId;
  final String? checkInId;
}

class _CheckinPhotoChoice {
  const _CheckinPhotoChoice({required this.item, required this.photo});
  final CheckIn item;
  final CheckInPhotoAsset photo;
}
