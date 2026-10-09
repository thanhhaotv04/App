import 'package:shared_preferences/shared_preferences.dart';

Future<String?> readSnapshot(SharedPreferences prefs, String key) async =>
    prefs.getString(key);

Future<bool> writeSnapshot(SharedPreferences prefs, String key, String value) =>
    prefs.setString(key, value);
