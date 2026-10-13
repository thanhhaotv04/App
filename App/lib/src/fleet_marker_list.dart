import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

const markerLabels = {
  'save_point': 'Save Point',
  'food': 'Food',
  'danger': 'Danger',
};

class FleetMarkerList extends StatefulWidget {
  const FleetMarkerList({this.revision = 0, super.key});
  final int revision;

  @override
  State<FleetMarkerList> createState() => _FleetMarkerListState();
}

class _FleetMarkerListState extends State<FleetMarkerList>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('esp32_navride/navigation');
  List<Map<String, dynamic>> _items = const [];
  Timer? _timer;
  bool _reading = false;
  bool _busy = false;
  bool _loading = true;
  String? _error;
  String? _warning;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load(refresh: true));
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_busy) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(FleetMarkerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) unawaited(_load(refresh: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      unawaited(_load(refresh: true));
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_reading) return;
    _reading = true;
    if (refresh && mounted) setState(() => _loading = true);
    try {
      final data = await _channel.invokeMapMethod<String, dynamic>(
        'getFleetMarkers',
        {'refresh': refresh},
      );
      if (!mounted) return;
      setState(() {
        _items = (data?['items'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _warning = data?['warning'] as String?;
        if (refresh) _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load markers. Refresh to try again.',
        );
      }
    } finally {
      _reading = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    var note = item['note'] as String? ?? '';
    var kind = markerLabels.containsKey(item['kind'])
        ? item['kind'] as String
        : 'save_point';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Edit marker'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: kind,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Marker type'),
                  items: markerLabels.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() => kind = value ?? kind),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: note,
                  onChanged: (value) => note = value,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText: 'Optional · visible to your fleet',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      await _mutate('editFleetMarker', item, {'kind': kind, 'note': note});
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete marker?'),
        content: const Text(
          'This deletes the marker and its photo. If offline, deletion is saved on this phone and completes when online. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete marker'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _mutate('deleteFleetMarker', item, const {});
    }
  }

  Future<void> _mutate(
    String method,
    Map<String, dynamic> item,
    Map<String, dynamic> extra,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _channel.invokeMethod<bool>(method, {'id': item['id'], ...extra});
      await _load();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save this change. Check your account and phone storage, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo(Map<String, dynamic> item) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    MemoryImage? image;
    try {
      final encoded = await _channel.invokeMethod<String>(
        'getFleetMarkerPhoto',
        {'id': item['id']},
      );
      if (encoded == null) throw StateError('Photo unavailable');
      image = MemoryImage(base64Decode(encoded));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(markerLabels[item['kind']] ?? 'Marker photo'),
          content: Image(
            image: image!,
            fit: BoxFit.contain,
            errorBuilder: (_, error, stack) =>
                const Text('Could not display this photo.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Photo unavailable. If already synced, connect to the internet and refresh.',
        );
      }
    } finally {
      await image?.evict();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(height: 32),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        children: [
          Text('Saved markers', style: Theme.of(context).textTheme.titleMedium),
          TextButton.icon(
            onPressed: _busy || _reading ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
      if (_loading || _busy) const LinearProgressIndicator(),
      if (_warning != null) Text(_warning!),
      if (_error != null)
        Semantics(
          liveRegion: true,
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (!_loading && _items.isEmpty)
        const Text('No markers yet. Save a point during a Fleet ride.'),
      for (final item in _items)
        Padding(
          key: ValueKey('saved-marker-${item['id']}'),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                markerLabels[item['kind']] ?? 'Marker',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (DateTime.tryParse(item['capturedAt'] as String? ?? '')
                  case final DateTime time)
                Text(DateFormat('dd MMM yyyy · HH:mm').format(time.toLocal())),
              Text(
                '${item['status'] ?? 'Saved on phone'}${item['deleting'] == true ? ' · deletion pending' : ''}',
              ),
              if ((item['note'] as String? ?? '').isNotEmpty)
                Text(item['note'] as String),
              Wrap(
                spacing: 8,
                children: [
                  if (item['hasPhoto'] == true && item['deleting'] != true)
                    TextButton.icon(
                      onPressed: _busy ? null : () => _photo(item),
                      icon: const Icon(Icons.photo_outlined),
                      label: const Text('View photo'),
                    ),
                  if (item['editable'] == true) ...[
                    TextButton(
                      onPressed: _busy ? null : () => _edit(item),
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _delete(item),
                      child: const Text('Delete'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      if (_items.length >= 200)
        const Text(
          'Showing the latest 200 markers. See older markers on the dashboard.',
        ),
    ],
  );
}
