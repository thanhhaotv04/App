import 'package:flutter/material.dart';

import '../models/sync_state.dart';
import '../models/checkin.dart';
import '../repositories/backend_config.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/sync_queue_repository.dart';
import '../repositories/sync_service.dart';

class SyncCenterScreen extends StatefulWidget {
  const SyncCenterScreen({super.key});

  @override
  State<SyncCenterScreen> createState() => _SyncCenterScreenState();
}

class _SyncCenterScreenState extends State<SyncCenterScreen> {
  final _queue = const SyncQueueRepository();
  List<SyncOperation> _operations = [];
  List<SyncConflict> _conflicts = [];
  Map<String, CheckIn> _checkIns = {};
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final operations = await _queue.loadOperations();
    final conflicts = await _queue.loadConflicts();
    final checkIns = await CheckInRepository().load();
    if (mounted) {
      setState(() {
        _operations = operations;
        _conflicts = conflicts;
        _checkIns = {for (final item in checkIns) item.id: item};
      });
    }
  }

  Future<void> _retry() async {
    setState(() => _working = true);
    try {
      final repo = CheckInRepository();
      final sync = SyncService(baseUrl: await BackendConfig.loadUrl());
      await repo.save(await sync.syncTwoWay(await repo.load()));
    } finally {
      if (mounted) setState(() => _working = false);
      await _load();
    }
  }

  Future<void> _resolve(SyncConflict conflict, bool keepLocal) async {
    setState(() => _working = true);
    try {
      final repo = CheckInRepository();
      if (keepLocal) {
        final sync = SyncService(baseUrl: await BackendConfig.loadUrl());
        final saved = await sync.forcePush(conflict.local);
        await repo.update(saved.copyWith(synced: true));
      } else {
        await repo.update(conflict.remote.copyWith(synced: true));
      }
      await _queue.completeForCheckIn(conflict.checkInId);
      await _queue.removeConflict(conflict.checkInId);
    } finally {
      if (mounted) setState(() => _working = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sync center'),
      actions: [
        IconButton(
          onPressed: _working ? null : _retry,
          tooltip: 'Retry all',
          icon: const Icon(Icons.sync),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(
          'Pending (${_operations.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (_operations.isEmpty)
          const ListTile(title: Text('Everything is synced.')),
        for (final item in _operations)
          ListTile(
            leading: Icon(
              item.type == SyncOperationType.deleteCheckIn
                  ? Icons.delete_outline
                  : Icons.cloud_upload_outlined,
            ),
            title: Text(
              item.type == SyncOperationType.deleteCheckIn
                  ? 'Delete check-in'
                  : 'Upload check-in',
            ),
            subtitle: Text(_operationStatus(item)),
          ),
        const Divider(height: 32),
        Text(
          'Conflicts (${_conflicts.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (_conflicts.isEmpty) const ListTile(title: Text('No conflicts.')),
        for (final conflict in _conflicts)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conflict.local.place,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    'Local: ${conflict.local.notes}\nServer: ${conflict.remote.notes}',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _working
                            ? null
                            : () => _resolve(conflict, true),
                        child: const Text('Keep local'),
                      ),
                      OutlinedButton(
                        onPressed: _working
                            ? null
                            : () => _resolve(conflict, false),
                        child: const Text('Keep server'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  String _operationStatus(SyncOperation operation) {
    final checkIn = _checkIns[operation.checkInId];
    final photoStatus = checkIn == null || checkIn.photoCount == 0
        ? ''
        : ' · ${checkIn.photoCount} photo(s) pending';
    if (operation.lastError.isEmpty) {
      return 'Waiting for connection$photoStatus';
    }
    return '${operation.lastError}\nAttempts: ${operation.attempts}$photoStatus';
  }
}
