# Experience Notes For Future Android Builders

This file records practical lessons learned while turning the Vietnam Map Checkin project into a Flutter Android app.

## 1. Keep The First Android Goal Small

The first target should be:

```text
Build one APK that installs and runs on a real phone.
```

Do not start with Play Store signing, cloud backend, account system, push notifications, and app update automation at the same time. Build the smallest installable APK first, then add features.

## 2. Android `127.0.0.1` Is Not The PC

On the PC:

```text
http://127.0.0.1:3000
```

means the PC.

On the phone:

```text
http://127.0.0.1:3000
```

means the phone itself.

For a phone to talk to a backend running on the PC, use the PC LAN IP:

```text
http://192.168.x.x:3000
```

Both devices must be on the same Wi-Fi, and the firewall must allow the Node.js backend port.

## 3. Local Photo Storage Is Better Than Backend-Only Storage

Backend-only photo storage means:

- Photos disappear from the app when backend is offline.
- Phone must always reach the PC to view photos.
- It is less private by default.

Better approach:

1. Copy selected photo into app-private storage first.
2. Store the local reference in the check-in.
3. Upload a copy to backend only if backend is available.
4. Display local photo first, backend photo as fallback.

Android private folder used in this project:

```text
/data/user/0/com.example.vietnam_map_01/files/vietnam_map_checkin_images
```

This avoids broad storage permissions and keeps user-selected photos private to the app.

## 4. Avoid Unnecessary Native Packages

Some packages pull native hooks or platform dependencies that can trigger Windows Smart App Control or slow builds.

Observed risk:

- `package_info_plus`
- `path_provider`
- packages that pull `objective_c`, `jni`, or extra native build hooks

In this project, simple alternatives were used:

- App version is kept in `lib/src/app_version.dart`.
- Android private paths are computed directly for this app.
- Windows local image folder uses `%LOCALAPPDATA%`.

Use native packages only when they provide clear value that cannot be achieved simply.

## 5. Kotlin Incremental Cache Can Fail On Windows Multi-Drive Setups

This project is on `D:`, while Pub cache is on `C:`.

Kotlin build error encountered:

```text
this and base files have different roots
Could not close incremental caches
```

Fix applied in `android/gradle.properties`:

```properties
kotlin.incremental=false
kotlin.incremental.useClasspathSnapshot=false
kotlin.compiler.execution.strategy=in-process
```

This makes Android builds slower but more reliable on this machine.

## 6. Build ARM64 APK For Modern Phones

Modern Android phones with MediaTek Dimensity, Snapdragon, Exynos, or Tensor are normally `arm64`.

Use:

```powershell
flutter build apk --release --target-platform android-arm64
```

This avoids wasting time building `android-arm` and `android-x64` when the target is a real modern phone.

## 7. Android Cannot Silently Self-Update Sideloaded Apps

Normal sideloaded Android apps cannot update themselves silently.

Allowed practical flow:

1. App checks backend for latest version.
2. App downloads APK over same Wi-Fi.
3. App opens Android Package Installer.
4. User confirms installation.

This project implements that LAN update flow with:

- `backend/releases/latest.json`
- `backend/releases/app-release.apk`
- `AppUpdateService`
- Android `FileProvider`
- Android `REQUEST_INSTALL_PACKAGES`

The user may need to allow installs from this app/source in Android settings.

## 8. Backend Is Useful But Should Be Optional

For this app, backend handles:

- Photo backup to PC.
- Two-way sync.
- Serving images from PC.
- Serving APK updates.

But the app should still work offline:

- Local check-ins use `SharedPreferences`.
- Local photos use app-private storage.
- Backend URL can be configured later in Settings.

## 9. Prefer Local-First Data Design

Local-first behavior improves field use:

- User can check in without network.
- Photos remain visible without backend.
- Sync can happen later.

Current merge strategy:

- Check-ins have stable `id`.
- Backend avoids duplicate `id`.
- Sync merges by `id`.
- Newest/most complete record wins.

This is good enough for personal use. For multi-user production, add a real database and conflict policy.

## 10. Android HTTP Needs Manifest Setup

For local LAN backend over HTTP, Android needs:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

and for cleartext HTTP:

```xml
android:usesCleartextTraffic="true"
```

For production, prefer HTTPS and remove broad cleartext usage.

## 11. FileProvider Is Required To Install Downloaded APK

Android apps should not pass raw file paths to other apps.

Use `FileProvider` to expose a safe content URI:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
```

Then open installer with:

```kotlin
Intent.ACTION_VIEW
application/vnd.android.package-archive
Intent.FLAG_GRANT_READ_URI_PERMISSION
```

## 12. Version Updates Need Two Places

For LAN update to detect a newer version:

1. Increase local app version:

```text
lib/src/app_version.dart
```

2. Increase backend manifest version:

```text
backend/releases/latest.json
```

If `latest.json.versionCode` is not greater than `AppVersion.versionCode`, the app will say it is already up to date.

## 13. Test Checklist Before Sharing APK

Run:

```powershell
flutter analyze
flutter test
node --check backend\server.js
flutter build apk --release --target-platform android-arm64
```

Manual Android checks:

- App installs.
- Login/app picker opens.
- Map renders correctly.
- New check-in saves without backend.
- Photo remains visible after app restart.
- Backend sync works after setting LAN IP.
- LAN update check can reach backend.

## 14. Store-Ready Work Still Needed

For Play Store or public release, do not ship with the current debug signing setup.

Still needed:

- Real package id, not `com.example.vietnam_map_01`.
- Release keystore and signing config.
- App icon and splash screen.
- HTTPS production backend.
- Privacy policy.
- Clear data deletion/export policy.
- More tests around sync and photo deletion.

## 15. Practical Rule

When something breaks, reduce the problem:

1. Make local-only app work.
2. Make backend sync work.
3. Make release build work.
4. Make update flow work.

Do not debug all four at once.
