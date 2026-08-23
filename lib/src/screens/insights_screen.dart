import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../models/checkin.dart';
import '../repositories/backup_service.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/vietnam_regions.dart';
import '../repositories/wishlist_repository.dart';
import '../theme/app_colors.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _repo = CheckInRepository();
  final _wishlistRepo = WishlistRepository();
  final _backup = const BackupService();
  List<CheckIn> _items = [];
  Set<String> _wishlist = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repo.load();
    final wishlist = await _wishlistRepo.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _wishlist = wishlist;
    });
  }

  Future<void> _copyExport() async {
    await Clipboard.setData(ClipboardData(text: _backup.encode(_items)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Export copied.')));
  }

  Future<void> _copyTravelRecap() async {
    await Clipboard.setData(ClipboardData(text: _travelRecap()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Travel recap copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final visited = _items.map((item) => item.city).toSet();
    final favorites = _items.where((item) => item.favorite).length;
    final waiting = _items.where((item) => !item.synced).length;
    final rated = _items.where((item) => item.rating > 0).toList();
    final averageRating = rated.isEmpty
        ? 0.0
        : rated.map((item) => item.rating).reduce((a, b) => a + b) /
              rated.length;
    final topTags = _topTags(_items);
    final topProvince = _topProvince(_items);
    final achievements = _achievements(_items);
    final regionProgress = _regionProgress(_items);
    final monthlyCounts = _monthlyCounts(_items);
    final activeDays = _activeDays(_items);
    final currentStreak = _currentStreak(_items);
    final progress = (visited.length / 63).clamp(0.0, 1.0);
    final latest = _items.isEmpty
        ? null
        : (_items.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
              .first;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.bg, colors.bg2],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth > 960
              ? (constraints.maxWidth - 900) / 2
              : 18.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Travel insights',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A calm overview of the places and memories you keep.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _load,
                    tooltip: 'Reload',
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, metricsConstraints) {
                  final columns = metricsConstraints.maxWidth >= 620 ? 4 : 2;
                  final width =
                      (metricsConstraints.maxWidth - (columns - 1) * 12) /
                      columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _MetricCard(
                        width: width,
                        icon: Icons.bookmark_added_outlined,
                        label: 'Check-ins',
                        value: '${_items.length}',
                      ),
                      _MetricCard(
                        width: width,
                        icon: Icons.map_outlined,
                        label: 'Provinces',
                        value: '${visited.length}/63',
                      ),
                      _MetricCard(
                        width: width,
                        icon: Icons.favorite_outline,
                        label: 'Favorites',
                        value: '$favorites',
                      ),
                      _MetricCard(
                        width: width,
                        icon: Icons.cloud_upload_outlined,
                        label: 'Waiting sync',
                        value: '$waiting',
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (_items.isEmpty) ...[
                _InsightCard(
                  icon: Icons.add_location_alt_outlined,
                  title: 'Start your travel story',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add your first place from the map. You can save it offline and enrich it with photos later.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => context.go('/map'),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Open map'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _InsightCard(
                icon: Icons.bookmark_added_outlined,
                title: 'Wishlist',
                child: _wishlist.isEmpty
                    ? Text(
                        'Tap a province on the map and save it here as your next destination.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _wishlist
                            .map((province) => Chip(label: Text(province)))
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.map_outlined,
                title: 'Vietnam coverage',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label:
                          '${(progress * 100).toStringAsFixed(1)} percent of Vietnam province coverage complete',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 12,
                          backgroundColor: colors.panel2,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}% complete · ${63 - visited.length} province(s) left',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/map'),
                      icon: const Icon(Icons.explore_outlined),
                      label: const Text('Explore the map'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.public_outlined,
                title: 'Progress by 8 regions',
                child: Column(
                  children: regionProgress
                      .map((progress) => _RegionProgressRow(progress: progress))
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.calendar_month_outlined,
                title: 'Travel rhythm',
                child: _TravelRhythm(
                  monthlyCounts: monthlyCounts,
                  activeDays: activeDays,
                  currentStreak: currentStreak,
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.star_outline,
                title: 'Memory score',
                child: Text(
                  rated.isEmpty
                      ? 'No rated memories yet.'
                      : 'Average ${averageRating.toStringAsFixed(1)}/5 from ${rated.length} rated check-in(s).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.sell_outlined,
                title: 'Top tags',
                child: topTags.isEmpty
                    ? Text(
                        'No tags yet.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: topTags
                            .map(
                              (entry) => Chip(
                                label: Text('${entry.key} (${entry.value})'),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.emoji_events_outlined,
                title: 'Achievements',
                child: achievements.isEmpty
                    ? Text(
                        'Create a check-in, add a photo, rate a memory, or mark a favorite to unlock achievements.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: achievements
                            .map(
                              (achievement) => Chip(
                                avatar: Icon(achievement.icon, size: 18),
                                label: Text(achievement.label),
                              ),
                            )
                            .toList(),
                      ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.place_outlined,
                title: 'Most visited province',
                child: Text(
                  topProvince == null
                      ? 'No province data yet.'
                      : '${topProvince.key} leads with ${topProvince.value} check-in(s).',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.route_outlined,
                title: 'Next trip idea',
                child: Text(
                  _nextTripIdea(visited),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.history,
                title: 'Latest memory',
                child: Text(
                  latest == null
                      ? 'Create your first check-in from the map.'
                      : '${latest.place}, ${latest.city} · ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(latest.createdAt))}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.ios_share_outlined,
                title: 'Portable backup',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _items.isEmpty ? null : _copyExport,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copy JSON export'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.auto_stories_outlined,
                title: 'Travel recap',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create a short, privacy-friendly summary of your journey to paste into a message or note.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _items.isEmpty ? null : _copyTravelRecap,
                      icon: const Icon(Icons.copy_outlined),
                      label: const Text('Copy travel recap'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<MapEntry<String, int>> _topTags(List<CheckIn> items) {
    final counts = <String, int>{};
    for (final item in items) {
      for (final tag in item.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(8).toList();
  }

  List<_RegionProgress> _regionProgress(List<CheckIn> items) {
    return VietnamRegions.all.map((region) {
      final visited = items
          .where((item) => VietnamRegions.forProvince(item.city) == region.name)
          .map((item) => VietnamRegions.normalize(item.city))
          .toSet()
          .length;
      final checkins = items
          .where((item) => VietnamRegions.forProvince(item.city) == region.name)
          .length;
      return _RegionProgress(
        name: region.name,
        visited: visited,
        total: region.provinces.length,
        checkins: checkins,
      );
    }).toList();
  }

  List<int> _monthlyCounts(List<CheckIn> items) {
    final counts = List<int>.filled(12, 0);
    for (final item in items) {
      final month = DateTime.fromMillisecondsSinceEpoch(item.createdAt).month;
      counts[month - 1] += 1;
    }
    return counts;
  }

  int _activeDays(List<CheckIn> items) => items
      .map((item) {
        final date = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
        return DateTime(date.year, date.month, date.day);
      })
      .toSet()
      .length;

  int _currentStreak(List<CheckIn> items) {
    final dates =
        items
            .map((item) {
              final date = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
              return DateTime(date.year, date.month, date.day);
            })
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    if (dates.isEmpty) return 0;
    var streak = 1;
    for (var index = 1; index < dates.length; index += 1) {
      if (dates[index - 1].difference(dates[index]).inDays != 1) break;
      streak += 1;
    }
    return streak;
  }

  String _travelRecap() {
    if (_items.isEmpty) return 'VietNam Map Checkin\nNo memories yet.';
    final sorted = _items.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final visited = _items
        .map((item) => VietnamRegions.normalize(item.city))
        .toSet()
        .length;
    final photos = _items.where((item) => item.hasPhoto).length;
    final regions = _regionProgress(_items)
      ..sort((a, b) => b.checkins.compareTo(a.checkins));
    final latest = sorted.first;
    final wishlist = _wishlist.take(5).join(', ');
    return [
      'VietNam Map Checkin - Travel recap',
      '${_items.length} check-in(s) in $visited province(s)',
      '$photos photo(s) saved · ${_items.where((item) => item.favorite).length} favorite(s)',
      if (regions.first.checkins > 0)
        'Most explored region: ${regions.first.name}',
      if (wishlist.isNotEmpty) 'Next on the wishlist: $wishlist',
      'Latest memory: ${latest.place}, ${latest.city}',
    ].join('\n');
  }

  MapEntry<String, int>? _topProvince(List<CheckIn> items) {
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.city] = (counts[item.city] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first;
  }

  List<_Achievement> _achievements(List<CheckIn> items) {
    final visited = items.map((item) => item.city).toSet().length;
    return [
      if (items.isNotEmpty)
        const _Achievement(Icons.flag_outlined, 'First memory'),
      if (visited >= 5) const _Achievement(Icons.map_outlined, '5 provinces'),
      if (visited >= 15)
        const _Achievement(Icons.explore_outlined, 'Regional explorer'),
      if (items.any((item) => item.hasPhoto))
        const _Achievement(Icons.photo_camera_outlined, 'Photo keeper'),
      if (items.any((item) => item.favorite))
        const _Achievement(Icons.favorite_outline, 'Favorite curator'),
      if (items.any((item) => item.rating >= 5))
        const _Achievement(Icons.star_outline, 'Five-star moment'),
      if (items.any((item) => !item.synced))
        const _Achievement(Icons.cloud_off_outlined, 'Offline ready'),
    ];
  }

  String _nextTripIdea(Set<String> visited) {
    const ideas = [
      'Hà Giang',
      'Lào Cai',
      'Quảng Ninh',
      'Huế',
      'Đà Nẵng',
      'Lâm Đồng',
      'Kiên Giang',
      'Cần Thơ',
    ];
    final next = ideas
        .where((city) => !visited.contains(city))
        .take(3)
        .toList();
    if (next.isEmpty) {
      return 'Your highlight list is covered. Pick a province with no photos yet.';
    }
    return 'Try ${next.join(', ')} next to balance north, central, and south memories.';
  }
}

class _RegionProgress {
  const _RegionProgress({
    required this.name,
    required this.visited,
    required this.total,
    required this.checkins,
  });

  final String name;
  final int visited;
  final int total;
  final int checkins;

  double get value => total == 0 ? 0 : visited / total;
}

class _RegionProgressRow extends StatelessWidget {
  const _RegionProgressRow({required this.progress});

  final _RegionProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  progress.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${progress.visited}/${progress.total} · ${progress.checkins} check-ins',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Semantics(
            label:
                '${progress.name}: ${progress.visited} of ${progress.total} provinces visited',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.value,
                minHeight: 9,
                backgroundColor: colors.panel2,
                color: colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TravelRhythm extends StatelessWidget {
  const _TravelRhythm({
    required this.monthlyCounts,
    required this.activeDays,
    required this.currentStreak,
  });

  final List<int> monthlyCounts;
  final int activeDays;
  final int currentStreak;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final maxCount = monthlyCounts.fold<int>(
      0,
      (maxValue, count) => count > maxValue ? count : maxValue,
    );
    const labels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$activeDays active check-in days',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            Text(
              'Recent streak: $currentStreak day(s)',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(monthlyCounts.length, (index) {
              final count = monthlyCounts[index];
              final height = maxCount == 0 ? 8.0 : 14 + 88 * count / maxCount;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '$count',
                        style: TextStyle(color: colors.muted, fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      Semantics(
                        label: '${labels[index]}: $count check-in(s)',
                        child: Container(
                          height: height,
                          decoration: BoxDecoration(
                            color: count == 0 ? colors.panel2 : colors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        labels[index],
                        style: TextStyle(color: colors.muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _Achievement {
  const _Achievement(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: colors.accent, size: 22),
            const SizedBox(height: 12),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
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
              Icon(icon, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
