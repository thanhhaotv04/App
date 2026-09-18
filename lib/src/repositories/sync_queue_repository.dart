import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/checkin.dart';
import '../models/sync_state.dart';

class SyncQueueRepository {
  const SyncQueueRepository({this.userName});

  final String? userName;
  static const _userKey = 'vmc-auth-user';
  static const _queuePrefix = 'vmc-sync-queue-';
  static const _conflictPrefix = 'vmc-sync-conflicts-';

  Future<List<SyncOperation>> loadOperations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _key(prefs, _queuePrefix));
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .whereType<Map>()
        .map(
          (value) => SyncOperation.fromJson(Map<String, dynamic>.from(value)),
        )
        .where((value) => value.id.isNotEmpty && value.checkInId.isNotEmpty)
        .toList();
  }

  Future<void> enqueueUpsert(String checkInId) =>
      _enqueue(checkInId, SyncOperationType.upsertCheckIn);

  Future<void> enqueueDelete(String checkInId) =>
      _enqueue(checkInId, SyncOperationType.deleteCheckIn);

  Future<void> _enqueue(String checkInId, SyncOperationType type) async {
    final operations = await loadOperations();
    operations.removeWhere((operation) => operation.checkInId == checkInId);
    operations.add(
      SyncOperation(
        id: const Uuid().v4(),
        checkInId: checkInId,
        type: type,
        queuedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await _saveOperations(operations);
  }

  Future<void> complete(String operationId) async {
    final operations = await loadOperations()
      ..removeWhere((operation) => operation.id == operationId);
    await _saveOperations(operations);
  }

  Future<void> completeForCheckIn(String checkInId) async {
    final operations = await loadOperations()
      ..removeWhere((operation) => operation.checkInId == checkInId);
    await _saveOperations(operations);
  }

  Future<void> fail(String operationId, Object error) async {
    final operations = await loadOperations();
    final index = operations.indexWhere(
      (operation) => operation.id == operationId,
    );
    if (index < 0) return;
    operations[index] = operations[index].copyWith(
      attempts: operations[index].attempts + 1,
      lastError: _friendlyError(error),
    );
    await _saveOperations(operations);
  }

  Future<List<SyncConflict>> loadConflicts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _key(prefs, _conflictPrefix));
    if (raw == null || raw.isEmpty) return [];
    return (jsonDecode(raw) as List)
        .whereType<Map>()
        .map((value) => SyncConflict.fromJson(Map<String, dynamic>.from(value)))
        .toList();
  }

  Future<void> saveConflict(CheckIn local, CheckIn remote) async {
    final conflicts = await loadConflicts()
      ..removeWhere((conflict) => conflict.checkInId == local.id)
      ..add(
        SyncConflict(
          checkInId: local.id,
          local: local,
          remote: remote,
          detectedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    await _saveConflicts(conflicts);
  }

  Future<void> removeConflict(String checkInId) async {
    final conflicts = await loadConflicts()
      ..removeWhere((conflict) => conflict.checkInId == checkInId);
    await _saveConflicts(conflicts);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await _key(prefs, _queuePrefix));
    await prefs.remove(await _key(prefs, _conflictPrefix));
  }

  Future<void> _saveOperations(List<SyncOperation> operations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      await _key(prefs, _queuePrefix),
      jsonEncode(operations.map((operation) => operation.toJson()).toList()),
    );
  }

  Future<void> _saveConflicts(List<SyncConflict> conflicts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      await _key(prefs, _conflictPrefix),
      jsonEncode(conflicts.map((conflict) => conflict.toJson()).toList()),
    );
  }

  Future<String> _key(SharedPreferences prefs, String prefix) async {
    final name = userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : prefs.getString(_userKey)?.trim() ?? '';
    if (name.isEmpty) throw StateError('Sign in before using sync.');
    return '$prefix${base64UrlEncode(utf8.encode(name.toLowerCase()))}';
  }

  static String _friendlyError(Object error) {
    final value = error.toString().replaceFirst('Exception: ', '');
    return value.length <= 180 ? value : '${value.substring(0, 177)}...';
  }
}
