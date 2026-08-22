import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/checkin.dart';
import '../repositories/backend_config.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/sync_service.dart';
import '../theme/app_colors.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _repo = CheckInRepository();
  late SyncService _sync = const SyncService();
  final _urlCtrl = TextEditingController(text: BackendConfig.defaultUrl);
  List<CheckIn> _items = [];
  bool _syncing = false;
  String _status = 'Not synced yet';

  bool get _usesLocalhost {
    final host = Uri.tryParse(_urlCtrl.text.trim())?.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost';
  }

  @override
  void initState() {
    super.initState();
    _loadUrl();
    _loadItems();
  }

  Future<void> _loadUrl() async {
    final url = await BackendConfig.loadUrl();
    if (!mounted) return;
    setState(() => _urlCtrl.text = url);
  }

  Future<void> _loadItems() async {
    final items = await _repo.load();
    if (!mounted) return;
    setState(() => _items = items);
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _syncTwoWay() async {
    setState(() {
      _syncing = true;
      _status = 'Syncing...';
    });
    try {
      await BackendConfig.saveUrl(_urlCtrl.text);
      final url = await BackendConfig.loadUrl();
      _sync = SyncService(baseUrl: url);
      final items = await _repo.load();
      final merged = await _sync.syncTwoWay(items);
      await _repo.save(merged);
      await _loadItems();
      if (!mounted) return;
      setState(() => _status = 'Synced ${merged.length} item(s) with backend');
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = 'Sync error: $err');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final waiting = _items.where((item) => !item.synced).toList();
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
          Text(
            'Sync & backend',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Your check-ins stay usable offline. Sync is an optional backup when your backend is available.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: colors.panel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _urlCtrl,
                    keyboardType: TextInputType.url,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Backend URL',
                      hintText: 'http://127.0.0.1:3000',
                    ),
                  ),
                  if (_usesLocalhost) ...[
                    const SizedBox(height: 12),
                    _ConnectionHint(
                      icon: Icons.phone_android_outlined,
                      title: 'Using a phone?',
                      message:
                          '127.0.0.1 points to the phone itself. Enter your computer\'s Wi-Fi address, for example http://192.168.1.10:3000.',
                    ),
                  ],
                  const SizedBox(height: 14),
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      children: [
                        Icon(
                          _syncing ? Icons.sync : Icons.cloud_outlined,
                          color: colors.accent,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _status,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Two-way sync pulls backend data, pushes local-only check-ins, and merges by check-in id.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colors.muted),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _syncing ? null : _syncTwoWay,
                      icon: _syncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_alt_outlined),
                      label: Text(
                        _syncing
                            ? 'Syncing memories…'
                            : waiting.isEmpty
                            ? 'Sync now'
                            : 'Sync ${waiting.length} waiting ${waiting.length == 1 ? 'memory' : 'memories'}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'Sync queue',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 8),
                      _QueueCount(count: waiting.length),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (waiting.isEmpty)
                    _QueueCard(
                      icon: Icons.cloud_done_outlined,
                      title: 'All local check-ins are marked synced.',
                      subtitle:
                          'Create or edit a check-in offline to see it here.',
                    )
                  else
                    ...waiting.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _QueueCard(
                          icon: item.hasPhoto
                              ? Icons.photo_outlined
                              : Icons.place_outlined,
                          title: '${item.place}, ${item.city}',
                          subtitle:
                              '${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.createdAt))} · ${item.source.toUpperCase()}',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionHint extends StatelessWidget {
  const _ConnectionHint({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.warning.withValues(alpha: 0.58)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colors.accent2),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(message, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueCount extends StatelessWidget {
  const _QueueCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: count == 0
            ? colors.good.withValues(alpha: 0.18)
            : colors.warning.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count == 0 ? 'All clear' : '$count waiting',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: count == 0 ? colors.good : colors.accent2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: colors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
