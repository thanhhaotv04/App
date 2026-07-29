import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../models/checkin.dart';
import '../repositories/backend_config.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/local_image_storage.dart';
import '../repositories/sync_service.dart';
import '../theme/app_colors.dart';
import '../widgets/checkin_photo.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _repo = CheckInRepository();
  List<CheckIn> _items = [];
  String _backendUrl = BackendConfig.defaultUrl;

  String _photoUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_backendUrl/$path';
  }

  void _openPhoto(CheckIn item) {
    if (!item.hasPhoto) return;
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.place,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: CheckInPhoto(
                    item: item,
                    remoteUrl: _photoUrl,
                    fit: BoxFit.contain,
                    errorText: 'Photo not found locally or on the backend.',
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _replacePhoto(item);
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Change photo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _deletePhoto(item);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete photo'),
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

  Future<void> _replacePhoto(CheckIn item) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final localPhoto = await LocalImageStorage.saveImage(
      bytes: bytes,
      originalName: picked.name,
      city: item.city,
      createdAt: item.createdAt,
    );
    var updated = item.copyWith(localPhoto: localPhoto, synced: false);
    try {
      final remote = await SyncService(
        baseUrl: _backendUrl,
      ).push(updated, photoBytes: bytes, photoFileName: picked.name);
      updated = remote.copyWith(localPhoto: localPhoto, synced: true);
    } catch (_) {
      // The local replacement remains available while offline.
    }
    await LocalImageStorage.deleteImage(item.localPhoto);
    await _repo.update(updated);
    await _load();
  }

  Future<void> _deletePhoto(CheckIn item) async {
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
      await SyncService(baseUrl: _backendUrl).deletePhoto(item.id);
    } catch (_) {
      // Keep the local deletion and retry when the backend is available.
    }
    await _repo.deletePhoto(item.id);
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _loadBackendUrl();
    _load();
  }

  Future<void> _loadBackendUrl() async {
    final url = await BackendConfig.loadUrl();
    if (!mounted) return;
    setState(() => _backendUrl = url);
  }

  Future<void> _load() async {
    final items = await _repo.load();
    if (!mounted) return;
    setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final grouped = <String, List<CheckIn>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.city, () => []).add(item);
    }
    final cities = grouped.keys.toList()..sort();

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
          _SectionHeader(
            title: 'Check-in history',
            action: TextButton(onPressed: _load, child: const Text('Reload')),
          ),
          const SizedBox(height: 18),
          if (cities.isEmpty)
            _EmptyHistoryCard(
              text:
                  'No check-ins yet. Go back to the map to create the first one.',
              colors: colors,
            ),
          for (final city in cities)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: colors.panel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: colors.line),
              ),
              child: ExpansionTile(
                iconColor: colors.accent,
                collapsedIconColor: colors.muted,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                minTileHeight: 76,
                title: Text(
                  '$city (${grouped[city]!.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: grouped[city]!
                    .map(
                      (item) => Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: colors.panel2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colors.line),
                        ),
                        child: ListTile(
                          leading: _HistoryThumbnail(
                            item: item,
                            photoUrl: _photoUrl,
                            onTap: () => _openPhoto(item),
                          ),
                          title: Text(
                            item.place,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.createdAt))} · ${item.source.toUpperCase()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: colors.muted,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard({required this.text, required this.colors});

  final String text;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.line),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _HistoryThumbnail extends StatelessWidget {
  const _HistoryThumbnail({
    required this.item,
    required this.photoUrl,
    required this.onTap,
  });

  final CheckIn item;
  final String Function(String path) photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    if (!item.hasPhoto) {
      return CircleAvatar(
        backgroundColor: item.synced
            ? colors.good.withValues(alpha: 0.22)
            : colors.warning.withValues(alpha: 0.25),
        foregroundColor: item.synced ? colors.good : colors.accent2,
        child: Icon(
          item.synced ? Icons.cloud_done : Icons.cloud_upload_outlined,
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: CheckInPhoto(
            item: item,
            remoteUrl: photoUrl,
            emptyIconSize: 20,
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(color: colors.text),
        ),
        action ?? const SizedBox.shrink(),
      ],
    );
  }
}
