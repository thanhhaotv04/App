import 'package:shared_preferences/shared_preferences.dart';

class PrivacySettings {
  const PrivacySettings({this.localOnly = false, this.hideLocation = false});

  static const localOnlyKey = 'vmc-privacy-local-only';
  static const hideLocationKey = 'vmc-privacy-hide-location';

  final bool localOnly;
  final bool hideLocation;

  static Future<PrivacySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PrivacySettings(
      localOnly: prefs.getBool(localOnlyKey) ?? false,
      hideLocation: prefs.getBool(hideLocationKey) ?? false,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(localOnlyKey, localOnly);
    await prefs.setBool(hideLocationKey, hideLocation);
  }

  PrivacySettings copyWith({bool? localOnly, bool? hideLocation}) =>
      PrivacySettings(
        localOnly: localOnly ?? this.localOnly,
        hideLocation: hideLocation ?? this.hideLocation,
      );
}
