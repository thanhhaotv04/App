import 'package:flutter/material.dart';

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
  final _urlCtrl = TextEditingController(text: 'http://127.0.0.1:3000');
  bool _syncing = false;
  String _status = 'Not synced yet';

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    final url = await BackendConfig.loadUrl();
    if (!mounted) return;
    setState(() => _urlCtrl.text = url);
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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.bg, colors.bg2],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Sync & backend', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: colors.panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                      Icon(_syncing ? Icons.sync : Icons.cloud_outlined, color: colors.accent),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_status, style: Theme.of(context).textTheme.titleMedium)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Two-way sync pulls backend data, pushes local-only check-ins, and merges by check-in id.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _syncing ? null : _syncTwoWay,
                    icon: _syncing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_alt_outlined),
                    label: const Text('Sync now'),
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
