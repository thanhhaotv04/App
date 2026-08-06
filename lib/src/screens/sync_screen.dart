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
                    decoration: const InputDecoration(
                      labelText: 'Backend URL',
                      hintText: 'http://127.0.0.1:3000',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
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
                  const SizedBox(height: 12),
                  Text(
                    'Two-way sync pulls backend data, pushes local-only check-ins, and merges by check-in id.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: colors.muted),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _syncing ? null : _syncTwoWay,
                    icon: _syncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_alt_outlined),
                    label: const Text('Sync now'),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Sync queue',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  if (waiting.isEmpty)
                    _QueueCard(
                      icon: Icons.cloud_done_outlined,
                      title: 'All local check-ins are marked synced.',
                      subtitle: 'Create or edit a check-in offline to see it here.',
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
