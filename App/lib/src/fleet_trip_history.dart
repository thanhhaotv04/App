import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class FleetTripHistory extends StatefulWidget {
  const FleetTripHistory({super.key});

  @override
  State<FleetTripHistory> createState() => _FleetTripHistoryState();
}

class _TripHistoryResult {
  const _TripHistoryResult({this.items, this.failed = false});

  final List<dynamic>? items;
  final bool failed;
}

class _FleetTripHistoryState extends State<FleetTripHistory> {
  static const _channel = MethodChannel('esp32_navride/navigation');
  Future<_TripHistoryResult>? _history;

  void _load() {
    final history = _channel
        .invokeListMethod<dynamic>('getFleetTrips')
        .then<_TripHistoryResult>(
          (items) => _TripHistoryResult(items: items),
          onError: (Object error, StackTrace stackTrace) =>
              const _TripHistoryResult(failed: true),
        );
    setState(() {
      _history = history;
    });
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    // Keep expanded state separate from the parent Trips page's scroll offset.
    key: const PageStorageKey('fleet-recent-trips'),
    internalAddSemanticForOnTap: true,
    tilePadding: EdgeInsets.zero,
    title: const Text('Recent trips'),
    subtitle: const Text('Cloud history · newest first'),
    onExpansionChanged: (expanded) {
      if (expanded && _history == null) _load();
    },
    children: [
      FutureBuilder<_TripHistoryResult>(
        future: _history,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            );
          }
          if (snapshot.data?.failed ?? false) {
            return const Text(
              'History unavailable. Connect to the internet and refresh. Unsynced trips stay on your phone.',
            );
          }
          final items = snapshot.data?.items ?? const [];
          if (items.isEmpty) {
            return const Text(
              'No synced trips yet. Private rides are not stored in Fleet.',
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route),
                  title: Text(_date(item['startedAt'] as String?)),
                  subtitle: Text(
                    (item['endedAt'] as String? ?? '').isEmpty
                        ? 'End time not synced yet'
                        : 'Ended · ${_date(item['endedAt'] as String?)}',
                  ),
                ),
              if (items.length >= 100)
                const Text('Latest 100 trips. See more on the dashboard.'),
            ],
          );
        },
      ),
      TextButton.icon(
        onPressed: _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh history'),
      ),
    ],
  );

  String _date(String? value) {
    final time = DateTime.tryParse(value ?? '');
    return time == null
        ? 'Unknown time'
        : DateFormat('dd MMM yyyy · HH:mm').format(time.toLocal());
  }
}
