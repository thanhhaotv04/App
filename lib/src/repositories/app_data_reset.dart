import 'package:shared_preferences/shared_preferences.dart';

import 'checkin_repository.dart';
import 'local_image_storage.dart';

class AppDataReset {
  const AppDataReset._();

  static Future<void> clearCheckInsAndPhotos() async {
    await CheckInRepository.clearCurrentData();
    await LocalImageStorage.deleteAllImages();
  }

  static Future<void> clearAllLocalData() async {
    await LocalImageStorage.deleteAllImages(allUsers: true);
    await CheckInRepository.clearAllData();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
