# VietNam Map Checkin

Flutter app for saving travel check-ins on a Vietnam province map. The app was migrated from the original web app at `D:\thanhhao_ws\App\App_VietNam_Map` and keeps the same core idea: map-first check-in, photos, history, sync, and local-first usage.

## What The App Does

- Shows an interactive Vietnam province map.
- Click a province to open province detail.
- Add check-ins with province, place, notes, date/time, and photo.
- Hover/tap provinces to see recent check-in photos.
- Colors provinces by check-in count:
  - `0`: no check-in
  - `1-2`
  - `3-5`
  - `6+`
- Shows recent check-ins with thumbnails.
- Shows check-in history grouped by city/province.
- Supports light and dark themes.
- Has login and app picker screens.
- Has Settings for backend URL, data import/export, sync, and LAN app updates.

## Privacy And Photo Storage

The Android app stores selected photos locally first.

Android private image folder:

```text
/data/user/0/com.example.vietnam_map_01/files/vietnam_map_checkin_images
```

Windows local image folder:

```text
%LOCALAPPDATA%\VietNamMapCheckin\vietnam_map_checkin_images
```

This folder only contains photos selected inside the app. On Android it is app-private storage, so normal apps cannot browse it directly. When a check-in is deleted, its local photo is deleted too.

Backend upload is optional. If the backend is running, the app also uploads a copy of the photo to the PC backend.

## Backend

The included Node.js backend is local-first and file-based. It is useful for:

- Receiving uploaded photos from the app.
- Serving photos back to Flutter.
- Syncing check-ins between devices.
- Serving APK update files over the same Wi-Fi.

Start backend:

```powershell
cd D:\thanhhao_ws\App\App_VietNam_Map_Flutter\vietnam_map_01
npm run backend
```

Default backend URL:

```text
http://127.0.0.1:3000
```

On Android phone, use the PC LAN IP instead:

```text
http://<PC_LAN_IP>:3000
```

Example:

```text
http://192.168.1.10:3000
```

## Main Features

### Map

- GeoJSON-based Vietnam province map.
- Province hover/tap detection.
- Province tooltip with recent photos.
- Province detail panel with all check-ins in that province.
- Add check-in directly from a province.

### Check-in Photo Flow

1. User chooses a photo.
2. App copies the photo into local private storage.
3. If backend is reachable, app uploads a copy to backend.
4. App displays local photo first, backend photo as fallback.

### History

- Grouped check-in list by province/city.
- Thumbnail preview.
- Full photo preview.
- Works with local photos and backend photos.

### Sync

- Two-way sync with backend.
- Pulls backend check-ins.
- Pushes local-only check-ins.
- Merges by check-in id.

### Settings

- Toggle theme.
- Save Backend URL.
- Import JSON.
- Export JSON.
- Load sample data.
- Delete all local data.
- Show private image storage folder.
- Check for app updates over LAN.

### LAN App Update

Android cannot silently self-update normal sideloaded apps. This app supports a practical LAN update flow:

1. PC runs backend.
2. Backend exposes latest APK.
3. Phone downloads APK over same Wi-Fi.
4. Android asks the user to confirm installation.

Backend update files:

```text
backend\releases\latest.json
backend\releases\app-release.apk
```

## Build And Run

Install Flutter dependencies:

```powershell
flutter pub get
```

Run on Chrome:

```powershell
flutter run -d chrome
```

Run on Windows:

```powershell
flutter run -d windows
```

Build web release:

```powershell
flutter build web --release
```

Build Windows release:

```powershell
flutter build windows --release
```

Build Android APK for modern phones:

```powershell
flutter build apk --release --target-platform android-arm64
```

APK output:

```text
build\app\outputs\flutter-apk\app-release.apk
```

## Android Notes

- The APK is built for `android-arm64`.
- Works on modern MediaTek Dimensity, Snapdragon, Exynos, and Tensor phones.
- Tested build target is suitable for Android 16 phones.
- Current APK uses debug signing for easy sideload testing.
- For Play Store, create a real release signing key and change the package id.

## Verification Commands

```powershell
flutter analyze
flutter test
node --check backend\server.js
flutter build apk --release --target-platform android-arm64
```

## Important Files

- Flutter entry: `lib/main.dart`
- App router/gate: `lib/src/app.dart`
- Map screen: `lib/src/screens/map_screen.dart`
- History screen: `lib/src/screens/history_screen.dart`
- Sync screen: `lib/src/screens/sync_screen.dart`
- Settings screen: `lib/src/screens/settings_screen.dart`
- Local image storage: `lib/src/repositories/local_image_storage*.dart`
- Backend: `backend/server.js`
- Android release notes: `ANDROID_RELEASE_PLAN.md`
- Engineering notes: `EXPERIENCE.md`
