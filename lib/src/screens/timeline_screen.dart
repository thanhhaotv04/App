import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/checkin.dart';
import '../repositories/checkin_repository.dart';
import '../theme/app_colors.dart';

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  List<CheckIn> _items = [];

  @override
  void initState() {
    super.initState();
    CheckInRepository().load().then((value) {
      if (mounted) setState(() => _items = value);
    });
  }

  List<List<CheckIn>> get _trips {
    final sorted = [..._items]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final trips = <List<CheckIn>>[];
    for (final item in sorted) {
      if (trips.isEmpty ||
          item.createdAt - trips.last.last.createdAt >
              const Duration(hours: 48).inMilliseconds) {
        trips.add([item]);
      } else {
        trips.last.add(item);
      }
    }
    return trips.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Travel timeline')),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors.bg, colors.bg2]),
        ),
        child: _trips.isEmpty
            ? const Center(child: Text('No journeys yet.'))
            : ListView.separated(
                padding: const EdgeInsets.all(18),
                itemCount: _trips.length,
                separatorBuilder: (_, _) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final trip = _trips[index];
                  final distance = _distance(trip);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Journey ${_trips.length - index}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${DateFormat('d MMM yyyy').format(DateTime.fromMillisecondsSinceEpoch(trip.first.createdAt))} · ${trip.length} stop(s)${distance > 0 ? ' · ${distance.toStringAsFixed(1)} km' : ''}',
                          ),
                          const SizedBox(height: 12),
                          for (var i = 0; i < trip.length; i++)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                i == 0 ? Icons.trip_origin : Icons.location_on,
                                color: colors.accent,
                              ),
                              title: Text(trip[i].place),
                              subtitle: Text(
                                '${trip[i].city} · ${DateFormat('d MMM, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(trip[i].createdAt))}',
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
  }

  double _distance(List<CheckIn> trip) {
    var total = 0.0;
    for (var i = 1; i < trip.length; i++) {
      final a = trip[i - 1];
      final b = trip[i];
      if ((a.lat == 0 && a.lng == 0) || (b.lat == 0 && b.lng == 0)) continue;
      const radius = 6371.0;
      final lat1 = a.lat * pi / 180;
      final lat2 = b.lat * pi / 180;
      final dLat = (b.lat - a.lat) * pi / 180;
      final dLng = (b.lng - a.lng) * pi / 180;
      final h =
          sin(dLat / 2) * sin(dLat / 2) +
          cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
      total += radius * 2 * atan2(sqrt(h), sqrt(1 - h));
    }
    return total;
  }
}
