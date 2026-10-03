import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class NavRideStorage {
  static const _snapshotKey = 'esp32-navride.snapshot.v1';
  // Read the previous key once so renaming the app does not lose local data.
  static const _legacySnapshotKey = 'esp32-monitor.snapshot.v1';

  Future<NavRideSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw =
        prefs.getString(_snapshotKey) ?? prefs.getString(_legacySnapshotKey);
    if (raw == null) return _emptySnapshot();
    try {
      final snapshot = NavRideSnapshot.decode(raw);
      if (!prefs.containsKey(_snapshotKey)) {
        await prefs.setString(_snapshotKey, raw);
      }
      return snapshot;
    } catch (_) {
      return _emptySnapshot();
    }
  }

  Future<void> save(NavRideSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_snapshotKey, snapshot.encode())) {
      throw StateError('Could not save data. Please try again.');
    }
  }

  NavRideSnapshot _emptySnapshot() => const NavRideSnapshot(
    profileName: 'You',
    notices: [],
    tasks: [],
    config: NavRideConfig(),
  );
}
