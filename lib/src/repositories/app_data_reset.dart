import 'package:shared_preferences/shared_preferences.dart';

import 'local_image_storage.dart';

class AppDataReset {
  const AppDataReset._();

  static Future<void> clearCheckInsAndPhotos() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('vnm_checkins');
    await LocalImageStorage.deleteAllImages();
  }

  static Future<void> clearAllLocalData() async {
    await LocalImageStorage.deleteAllImages();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
