import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

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
  final _queryController = TextEditingController();
  List<CheckIn> _items = [];
  String _backendUrl = BackendConfig.defaultUrl;
  String _query = '';
  String _filter = 'all';
  String _sort = 'newest';

  String _photoUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$_backendUrl/$path';
  }

  void _openPhoto(CheckIn item) {
    if (!item.hasPhoto) return;
    final assets = item.photoItems;
    showDialog<void>(
      context: context,
      builder: (context) {
        var currentIndex = 0;
        return StatefulBuilder(
          builder: (context, setDialogState) => Dialog(
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
                            item.album.isEmpty
                                ? item.place
                                : '${item.album} · ${item.place}',
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
                    child: PageView.builder(
                      itemCount: assets.length,
                      onPageChanged: (index) =>
                          setDialogState(() => currentIndex = index),
                      itemBuilder: (context, index) {
                        final asset = assets[index];
                        final assetItem = item.copyWith(
                          photo: asset.photo,
                          localPhoto: asset.localPhoto,
                          photos: const [],
                        );
                        return InteractiveViewer(
                          child: CheckInPhoto(
                            item: assetItem,
                            remoteUrl: _photoUrl,
                            fit: BoxFit.contain,
                            errorText:
                                'Photo not found locally or on the backend.',
                          ),
                        );
                      },
                    ),
                  ),
                  if (assets.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${assets.length} photos · swipe to browse',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
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
                            await _deletePhotoAsset(item, assets[currentIndex]);
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
        );
      },
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
      album: item.album,
      createdAt: item.createdAt,
    );
    final replacement = CheckInPhotoAsset(
      localPhoto: localPhoto,
      name: picked.name,
      createdAt: item.createdAt,
    );
    final nextPhotos = item.photoItems.isEmpty
        ? [replacement]
        : [replacement, ...item.photoItems.skip(1)];
    var updated = item.copyWith(
      photo: replacement.photo,
      localPhoto: replacement.localPhoto,
      photos: nextPhotos,
      synced: false,
    );
    try {
      final remote = await SyncService(
        baseUrl: _backendUrl,
      ).push(updated, photoBytes: bytes, photoFileName: picked.name);
      final sync = SyncService(baseUrl: _backendUrl);
      updated = sync.mergeLocalPhotos(remote.copyWith(synced: true), updated);
    } catch (_) {
      // The local replacement remains available while offline.
    }
    for (final photo in item.photoItems) {
      if (photo.localPhoto != replacement.localPhoto) {
        await LocalImageStorage.deleteImage(photo.localPhoto);
      }
    }
    await _repo.update(updated);
    await _load();
  }

  Future<void> _deletePhotoAsset(CheckIn item, CheckInPhotoAsset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this photo?'),
        content: Text(
          'Remove this photo from ${item.album.isEmpty ? item.place : item.album}?',
        ),
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
    final remaining = item.photoItems.where((photo) => photo != asset).toList();
    final primary = remaining.isEmpty ? null : remaining.first;
    var updated = item.copyWith(
      photo: primary?.photo ?? '',
      localPhoto: primary?.localPhoto ?? '',
      photos: remaining,
      synced: false,
    );
    await LocalImageStorage.deleteImage(asset.localPhoto);
    try {
      if (asset.photo.isNotEmpty) {
        final sync = SyncService(baseUrl: _backendUrl);
        final remote = await sync.deletePhotoAsset(item.id, asset.photo);
        updated = sync.mergeLocalPhotos(remote.copyWith(synced: true), updated);
      }
    } catch (_) {
      // Keep the local deletion and retry through two-way sync later.
    }
    await _repo.update(updated);
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
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters => _query.trim().isNotEmpty || _filter != 'all';

  void _clearFilters() {
    _queryController.clear();
    setState(() {
      _query = '';
      _filter = 'all';
    });
  }

  int _compareText(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());

  int _compareCheckIns(CheckIn a, CheckIn b) {
    final primary = switch (_sort) {
      'oldest' => a.createdAt.compareTo(b.createdAt),
      'rating' => b.rating.compareTo(a.rating),
      'city' => _compareText(a.city, b.city),
      _ => b.createdAt.compareTo(a.createdAt),
    };
    if (primary != 0) return primary;

    final date = _sort == 'oldest'
        ? a.createdAt.compareTo(b.createdAt)
        : b.createdAt.compareTo(a.createdAt);
    if (date != 0) return date;

    final city = _compareText(a.city, b.city);
    if (city != 0) return city;
    final place = _compareText(a.place, b.place);
    if (place != 0) return place;
    return a.id.compareTo(b.id);
  }

  int _latestDate(List<CheckIn> items) => items.fold(
    items.first.createdAt,
    (latest, item) => item.createdAt > latest ? item.createdAt : latest,
  );

  int _earliestDate(List<CheckIn> items) => items.fold(
    items.first.createdAt,
    (earliest, item) => item.createdAt < earliest ? item.createdAt : earliest,
  );

  int _highestRating(List<CheckIn> items) => items.fold(
    0,
    (highest, item) => item.rating > highest ? item.rating : highest,
  );

  List<String> _orderedCities(Map<String, List<CheckIn>> grouped) {
    final cities = grouped.keys.toList();
    cities.sort((a, b) {
      final aItems = grouped[a]!;
      final bItems = grouped[b]!;
      final primary = switch (_sort) {
        'oldest' => _earliestDate(aItems).compareTo(_earliestDate(bItems)),
        'rating' => _highestRating(bItems).compareTo(_highestRating(aItems)),
        'city' => _compareText(a, b),
        _ => _latestDate(bItems).compareTo(_latestDate(aItems)),
      };
      if (primary != 0) return primary;

      if (_sort == 'rating') {
        final recent = _latestDate(bItems).compareTo(_latestDate(aItems));
        if (recent != 0) return recent;
      }
      return _compareText(a, b);
    });
    return cities;
  }

  String _groupSummary(List<CheckIn> items) {
    final date = switch (_sort) {
      'oldest' => _earliestDate(items),
      _ => _latestDate(items),
    };
    final dateLabel = DateFormat(
      'dd MMM yyyy',
    ).format(DateTime.fromMillisecondsSinceEpoch(date));
    final countLabel =
        '${items.length} ${items.length == 1 ? 'memory' : 'memories'}';
    return switch (_sort) {
      'oldest' => '$countLabel · First $dateLabel',
      'rating' when _highestRating(items) > 0 =>
        '$countLabel · Best ${_highestRating(items)}/5',
      'rating' => '$countLabel · Not rated yet',
      _ => '$countLabel · Latest $dateLabel',
    };
  }

  List<CheckIn> get _visibleItems {
    final q = _query.trim().toLowerCase();
    final items = _items.where((item) {
      final matchesQuery =
          q.isEmpty ||
          item.city.toLowerCase().contains(q) ||
          item.place.toLowerCase().contains(q) ||
          item.notes.toLowerCase().contains(q) ||
          item.tags.any((tag) => tag.toLowerCase().contains(q));
      final matchesFilter = switch (_filter) {
        'favorites' => item.favorite,
        'unsynced' => !item.synced,
        'photos' => item.hasPhoto,
        'rated' => item.rating > 0,
        _ => true,
      };
      return matchesQuery && matchesFilter;
    }).toList();
    items.sort(_compareCheckIns);
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final grouped = <String, List<CheckIn>>{};
    final visible = _visibleItems;
    for (final item in visible) {
      grouped.putIfAbsent(item.city, () => []).add(item);
    }
    final cities = _orderedCities(grouped);

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
            action: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ),
          const SizedBox(height: 18),
          _HistoryTools(
            query: _query,
            queryController: _queryController,
            filter: _filter,
            sort: _sort,
            total: visible.length,
            hasActiveFilters: _hasActiveFilters,
            onQueryChanged: (value) => setState(() => _query = value),
            onFilterChanged: (value) =>
                setState(() => _filter = value ?? 'all'),
            onSortChanged: (value) => setState(() => _sort = value ?? 'newest'),
            onClearFilters: _clearFilters,
          ),
          const SizedBox(height: 14),
          if (cities.isEmpty)
            _EmptyHistoryCard(
              icon: _items.isEmpty
                  ? Icons.add_location_alt_outlined
                  : Icons.search_off_outlined,
              title: _items.isEmpty
                  ? 'Start your travel story'
                  : 'No matches yet',
              text: _items.isEmpty
                  ? 'Add a first memory from the map. It will appear here by province.'
                  : 'Try a different search term or remove the current filters.',
              actionLabel: _items.isEmpty ? 'Open map' : 'Clear filters',
              actionIcon: _items.isEmpty
                  ? Icons.map_outlined
                  : Icons.filter_alt_off_outlined,
              onAction: _items.isEmpty
                  ? () => context.go('/map')
                  : _clearFilters,
              colors: colors,
            ),
          for (var index = 0; index < cities.length; index += 1)
            _ProvinceHistoryGroup(
              city: cities[index],
              summary: _groupSummary(grouped[cities[index]]!),
              items: grouped[cities[index]]!,
              initiallyExpanded: index == 0,
              colors: colors,
              photoUrl: _photoUrl,
              onOpenPhoto: _openPhoto,
            ),
        ],
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  const _EmptyHistoryCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.colors,
  });

  final IconData icon;
  final String title;
  final String text;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.panel2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colors.accent2),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTools extends StatelessWidget {
  const _HistoryTools({
    required this.query,
    required this.queryController,
    required this.filter,
    required this.sort,
    required this.total,
    required this.hasActiveFilters,
    required this.onQueryChanged,
    required this.onFilterChanged,
    required this.onSortChanged,
    required this.onClearFilters,
  });

  final String query;
  final TextEditingController queryController;
  final String filter;
  final String sort;
  final int total;
  final bool hasActiveFilters;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onFilterChanged;
  final ValueChanged<String?> onSortChanged;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Find a memory',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Semantics(
                label:
                    '$total ${total == 1 ? 'memory' : 'memories'} currently visible',
                child: ExcludeSemantics(
                  child: Text(
                    '$total ${total == 1 ? 'memory' : 'memories'}',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: colors.muted),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: queryController,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Search memories',
              hintText: 'place, note, tag...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        queryController.clear();
                        onQueryChanged('');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 620;
              final filterField = DropdownButtonFormField<String>(
                key: ValueKey('history-filter-$filter'),
                initialValue: filter,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(
                    value: 'favorites',
                    child: Text('Favorites'),
                  ),
                  DropdownMenuItem(
                    value: 'unsynced',
                    child: Text('Waiting sync'),
                  ),
                  DropdownMenuItem(value: 'photos', child: Text('Has photo')),
                  DropdownMenuItem(value: 'rated', child: Text('Rated')),
                ],
                onChanged: onFilterChanged,
                decoration: const InputDecoration(
                  labelText: 'Filter',
                  prefixIcon: Icon(Icons.filter_list_outlined),
                ),
              );
              final sortField = DropdownButtonFormField<String>(
                key: ValueKey('history-sort-$sort'),
                initialValue: sort,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'newest', child: Text('Newest')),
                  DropdownMenuItem(value: 'oldest', child: Text('Oldest')),
                  DropdownMenuItem(value: 'rating', child: Text('Top rated')),
                  DropdownMenuItem(value: 'city', child: Text('Province A-Z')),
                ],
                onChanged: onSortChanged,
                decoration: const InputDecoration(
                  labelText: 'Sort',
                  prefixIcon: Icon(Icons.sort_outlined),
                ),
              );
              if (narrow) {
                return Column(
                  children: [
                    filterField,
                    const SizedBox(height: 12),
                    sortField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: filterField),
                  const SizedBox(width: 12),
                  Expanded(child: sortField),
                ],
              );
            },
          ),
          if (hasActiveFilters) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onClearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear filters'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProvinceHistoryGroup extends StatelessWidget {
  const _ProvinceHistoryGroup({
    required this.city,
    required this.summary,
    required this.items,
    required this.initiallyExpanded,
    required this.colors,
    required this.photoUrl,
    required this.onOpenPhoto,
  });

  final String city;
  final String summary;
  final List<CheckIn> items;
  final bool initiallyExpanded;
  final AppColors colors;
  final String Function(String path) photoUrl;
  final ValueChanged<CheckIn> onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.line),
      ),
      child: ExpansionTile(
        key: PageStorageKey('history-province-$city'),
        initiallyExpanded: initiallyExpanded,
        iconColor: colors.accent,
        collapsedIconColor: colors.muted,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        minTileHeight: 84,
        title: Text(city, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          summary,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.muted),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: items
            .map(
              (item) => _HistoryEntryCard(
                item: item,
                colors: colors,
                photoUrl: photoUrl,
                onOpenPhoto: () => onOpenPhoto(item),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({
    required this.item,
    required this.colors,
    required this.photoUrl,
    required this.onOpenPhoto,
  });

  final CheckIn item;
  final AppColors colors;
  final String Function(String path) photoUrl;
  final VoidCallback onOpenPhoto;

  @override
  Widget build(BuildContext context) {
    final details = StringBuffer(
      '${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.createdAt))} · ${item.source.toUpperCase()}',
    );
    if (item.rating > 0) details.write(' · ${item.rating}/5');
    if (item.tags.isNotEmpty) details.write(' · ${item.tagLine}');
    if (item.album.isNotEmpty) details.write(' · Album: ${item.album}');
    if (item.photoCount > 1) details.write(' · ${item.photoCount} photos');

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minLeadingWidth: 52,
        minVerticalPadding: 10,
        isThreeLine: true,
        leading: _HistoryThumbnail(
          item: item,
          photoUrl: photoUrl,
          onTap: onOpenPhoto,
        ),
        title: Text(
          item.place,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          details.toString(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: _HistoryStatus(item: item, colors: colors),
      ),
    );
  }
}

class _HistoryStatus extends StatelessWidget {
  const _HistoryStatus({required this.item, required this.colors});

  final CheckIn item;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final status = item.synced ? 'Synced' : 'Waiting to sync';
    final labels = [if (item.favorite) 'Favorite', status];
    return Semantics(
      label: labels.join(', '),
      child: ExcludeSemantics(
        child: SizedBox(
          width: 28,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.favorite)
                Tooltip(
                  message: 'Favorite',
                  child: Icon(Icons.favorite, size: 20, color: colors.accent2),
                ),
              Tooltip(
                message: status,
                child: Icon(
                  item.synced
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_upload_outlined,
                  size: 20,
                  color: item.synced ? colors.good : colors.accent2,
                ),
              ),
            ],
          ),
        ),
      ),
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
      return Semantics(
        image: true,
        label: item.synced ? 'No photo, synced' : 'No photo, waiting to sync',
        child: CircleAvatar(
          backgroundColor: item.synced
              ? colors.good.withValues(alpha: 0.22)
              : colors.warning.withValues(alpha: 0.25),
          foregroundColor: item.synced ? colors.good : colors.accent2,
          child: Icon(
            item.synced ? Icons.cloud_done : Icons.cloud_upload_outlined,
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: 'View photo from ${item.place}',
      child: InkWell(
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
