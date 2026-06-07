# Android Release Plan

## Assumptions

- Target phone is Android 16 or newer.
- The app talks to the local Node backend during testing.
- For a physical phone, `127.0.0.1` means the phone itself, not the PC. Use the PC LAN IP in Settings, for example `http://192.168.1.10:3000`.
- Current release APK is signed with the debug signing config. This is installable for testing, but not suitable for Play Store distribution.

## Completed Android Readiness Changes

1. Added Android internet permission.
2. Enabled cleartext HTTP traffic for local/LAN backend testing.
3. Changed Android app label to `VietNam Map Checkin`.
4. Kept upload/import support through `file_selector`, which supports Android.
5. Added local private image storage. New check-in photos are copied into the app-private folder first.

## Local Image Privacy

On Android, selected photos are copied into:

```text
/data/user/0/com.example.vietnam_map_01/files/vietnam_map_checkin_images
```

This is app-private storage. Other normal apps cannot browse this folder. If a check-in is deleted, its local image file is also deleted.

Backend upload is optional. If the backend is running, the app also uploads a copy to the backend folder. If the backend is offline, the local private copy still remains available in the app.

## Build Steps

```powershell
cd D:\thanhhao_ws\App\App_VietNam_Map_Flutter\vietnam_map_01
flutter build apk --release
```

Expected output:

```text
build\app\outputs\flutter-apk\app-release.apk
```

## Phone Testing Steps

1. Start backend on the PC:

```powershell
npm run backend
```

2. Find PC LAN IP:

```powershell
ipconfig
```

3. Install APK on the phone.
4. Open app > Settings > Backend URL.
5. Set URL to `http://<PC_LAN_IP>:3000`.
6. Tap `Save URL`.
7. Use `Sync now`, image upload, History, and Map province detail.

## Still Missing For Store-Ready Android

1. Real release signing key instead of debug signing.
2. Final package id instead of `com.example.vietnam_map_01`.
3. Production backend over HTTPS.
4. App icon and splash screen customization.
5. Privacy policy if uploading/storing personal photos.

## LAN Update Flow

Android does not allow silent self-updates for normal sideloaded apps. The app can download a newer APK from the backend over the same Wi-Fi, but Android will still ask the user to confirm installation.

Backend release files:

```text
backend\releases\latest.json
backend\releases\app-release.apk
```

Example `latest.json`:

```json
{
  "versionName": "1.0.1",
  "versionCode": 2,
  "apkFile": "app-release.apk",
  "notes": "New app update."
}
```

To publish a new LAN update:

1. Increase `versionCode` in `lib/src/app_version.dart`.
2. Increase `version` in `pubspec.yaml` if needed.
3. Build APK:

```powershell
flutter build apk --release --target-platform android-arm64
```

4. Copy APK:

```powershell
Copy-Item build\app\outputs\flutter-apk\app-release.apk backend\releases\app-release.apk -Force
```

5. Update `backend\releases\latest.json` with the new `versionCode`.
6. Start backend:

```powershell
npm run backend
```

7. On the phone, open Settings > Backend URL, set the PC LAN IP, then tap `Check for update`.
