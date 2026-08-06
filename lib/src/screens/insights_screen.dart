import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/checkin.dart';
import '../repositories/backup_service.dart';
import '../repositories/checkin_repository.dart';
import '../theme/app_colors.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _repo = CheckInRepository();
  final _backup = const BackupService();
  List<CheckIn> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _repo.load();
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _copyExport() async {
    await Clipboard.setData(ClipboardData(text: _backup.encode(_items)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Export copied.')));
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
                    child: Text(
                      'Travel insights',
                      style: Theme.of(context).textTheme.headlineMedium,
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
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(label: 'Check-ins', value: '${_items.length}'),
                  _MetricCard(
                    label: 'Visited provinces',
                    value: '${visited.length}/63',
                  ),
                  _MetricCard(label: 'Favorites', value: '$favorites'),
                  _MetricCard(label: 'Waiting sync', value: '$waiting'),
                ],
              ),
              const SizedBox(height: 16),
              _InsightCard(
                icon: Icons.map_outlined,
                title: 'Vietnam coverage',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: colors.panel2,
                        color: colors.accent,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${(progress * 100).toStringAsFixed(1)}% complete · ${63 - visited.length} province(s) left',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
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

class _Achievement {
  const _Achievement(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SizedBox(
      width: 210,
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
            Text(label, style: Theme.of(context).textTheme.bodySmall),
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
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
