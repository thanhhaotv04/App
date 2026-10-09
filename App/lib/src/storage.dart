import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class NavRideStorage {
  String? recoveryWarning;
  static const _snapshotKey = 'esp32-navride.snapshot.v1';
  // Read the previous key once so renaming the app does not lose local data.
  static const _legacySnapshotKey = 'esp32-monitor.snapshot.v1';

  Future<NavRideSnapshot> load() async {
    recoveryWarning = null;
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_snapshotKey) ?? prefs.getString(_legacySnapshotKey);
    if (raw == null) return _emptySnapshot();
    NavRideSnapshot snapshot;
    try {
      snapshot = NavRideSnapshot.decode(raw);
    } on Object {
      // Never replace unreadable JSON with an empty account. Recover only a
      // valid top-level object, retaining a byte-for-byte backup first.
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Saved data is not a snapshot.');
      }
      final notices = <Notice>[];
      final tasks = <TaskItem>[];
      if (data['notices'] is List) {
        for (final item in data['notices'] as List) {
          try {
            notices.add(Notice.fromJson(item as Map<String, dynamic>));
          } on Object {
            /* The original item remains in the backup. */
          }
        }
      }
      if (data['tasks'] is List) {
        for (final item in data['tasks'] as List) {
          try {
            tasks.add(TaskItem.fromJson(item as Map<String, dynamic>));
          } on Object {
            /* The original item remains in the backup. */
          }
        }
      }
      var config = const NavRideConfig();
      try {
        config = NavRideConfig.fromJson(data['config'] as Map<String, dynamic>);
      } on Object {
        /* Preserve the invalid config in the backup. */
      }
      snapshot = NavRideSnapshot(
        profileName: data['profileName'] is String
            ? data['profileName'] as String
            : 'You',
        notices: notices,
        tasks: tasks,
        config: config,
      );
      final backupKey =
          '$_snapshotKey.recovery.${DateTime.now().microsecondsSinceEpoch}';
      if (!await prefs.setString(backupKey, raw)) {
        throw StateError('Could not back up saved data.');
      }
      if (!await prefs.setString(_snapshotKey, snapshot.encode())) {
        throw StateError('Could not save recovered data.');
      }
      recoveryWarning =
          'Some saved items could not be read. Readable items were recovered; the original data is backed up on this phone.';
    }
    if (!prefs.containsKey(_snapshotKey) &&
        !await prefs.setString(_snapshotKey, raw)) {
      throw StateError('Could not migrate saved data.');
    }
    return snapshot;
  }

  Future<void> save(NavRideSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    // A caller must load/recover first; never overwrite externally corrupted data.
    final existing =
        prefs.getString(_snapshotKey) ?? prefs.getString(_legacySnapshotKey);
    if (existing != null) NavRideSnapshot.decode(existing);
    if (!await prefs.setString(_snapshotKey, snapshot.encode())) {
      throw StateError('Could not save data. Please try again.');
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where(
      (key) =>
          key == _snapshotKey ||
          key == _legacySnapshotKey ||
          key.startsWith('$_snapshotKey.recovery.'),
    )) {
      if (!await prefs.remove(key)) {
        throw StateError('Could not delete all saved data. Please try again.');
      }
    }
    recoveryWarning = null;
  }

  NavRideSnapshot _emptySnapshot() => const NavRideSnapshot(
    profileName: 'You',
    notices: [],
    tasks: [],
    config: NavRideConfig(),
  );
}
