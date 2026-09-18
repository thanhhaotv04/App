import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../models/checkin.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/vietnam_regions.dart';
import '../theme/app_colors.dart';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  final _repo = CheckInRepository();
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
    final visited = _items
        .map((item) => VietnamRegions.normalize(item.city))
        .where((name) => name.isNotEmpty)
        .toSet();
    final regionProgress = _regionProgress(_items);
    final monthlyCounts = _monthlyCounts(_items);
    final activeDays = _activeDays(_items);
    final currentStreak = _currentStreak(_items);
    final progress = (visited.length / 63).clamp(0.0, 1.0);
    final remaining = (63 - visited.length).clamp(0, 63);

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
              OutlinedButton.icon(
                onPressed: () => context.push('/timeline'),
                icon: const Icon(Icons.timeline_outlined),
                label: const Text('Open travel timeline'),
              ),
              const SizedBox(height: 18),
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
                      '${(progress * 100).toStringAsFixed(1)}% complete · $remaining province(s) left',
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
    return [
      'VietNam Map Checkin - Travel recap',
      '${_items.length} check-in(s) in $visited province(s)',
      '$photos photo(s) saved',
      if (regions.first.checkins > 0)
        'Most explored region: ${regions.first.name}',
      'Latest memory: ${latest.place}, ${latest.city}',
    ].join('\n');
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
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final height = maxCount == 0
                                ? 8.0
                                : 8 +
                                      (constraints.maxHeight - 8) *
                                          count /
                                          maxCount;
                            return Semantics(
                              label: '${labels[index]}: $count check-in(s)',
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  height: height.clamp(
                                    0.0,
                                    constraints.maxHeight,
                                  ),
                                  decoration: BoxDecoration(
                                    color: count == 0
                                        ? colors.panel2
                                        : colors.accent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            );
                          },
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
