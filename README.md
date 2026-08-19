# Task Reminder

## Overview

`Task Reminder` is a Flutter app for managing daily tasks and reminders. It can
run offline first, preview in the browser, export Android APK files, and sync
with a Node.js backend only when the user chooses to sync.

## What The App Can Do

- Create an offline account, sign in, and change the local password.
- Add tasks with notes, icons, priority or no priority, and estimated focus time.
- Use Smart Quick Add, for example: `Nộp báo cáo mai 9:30 !cao ~45p #laptop`.
- Schedule tasks for today, a specific day, a weekday, or one/many monthly dates.
- View My Day, progress, streak, total focus minutes, and quick snooze controls.
- View a monthly overview with task status by day.
- Sync data with the backend through `/api/task-reminder/data`.
- Check APK updates through `/api/update/latest`.

## Where Data Is Stored

- Local app data:
  - `task-reminder-tasks-v1`
  - `task-reminder-assignments-v1`
  - `task-reminder-backend-url`
  - `task-reminder-auth-user`
  - `task-reminder-auth-password`
- Backend data:
  - default folder: `backend/server-data/`
  - override with the `DATA_DIR` environment variable
- APK update files:
  - manifest: `backend/releases/latest.json`
  - release APK: `backend/releases/`

## Web Preview Commands

Start the backend when you want sync/update features:

```bash
cd backend
npm install
ALLOWED_ORIGINS=http://192.168.1.142:8081 npm start
```

Start the web preview:

```bash
flutter pub get
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8081
```

Open:

```text
http://192.168.1.142:8081
```

Backend URL for the Account tab:

```text
http://192.168.1.142:3002
```

The Backend URL is only needed in the Account tab when syncing data or checking
updates.

## APK Export Commands

Debug APK:

```bash
flutter build apk --debug
```

Output:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

Release APK:

```bash
./tools/build_release_apk.sh
```

Output:

```text
build/app/outputs/flutter-apk/app-release-task-reminder.apk
```

The script keeps Flutter's default `app-release.apk`, creates
`app-release-task-reminder.apk`, and copies it to `backend/releases/` so APK
files from multiple apps are easy to distinguish.

## Version Update Commands

1. Update `pubspec.yaml`, for example:

```yaml
version: 1.0.1+2
```

2. Build the release APK:

```bash
./tools/build_release_apk.sh
```

3. Confirm the APK copied to the backend release folder:

```bash
ls -lh backend/releases/app-release-task-reminder.apk
```

4. Update `backend/releases/latest.json`:

```json
{
  "versionName": "1.0.1",
  "versionCode": 2,
  "apkFile": "app-release-task-reminder.apk",
  "notes": "Feature updates and bug fixes."
}
```

5. Restart the backend:

```bash
cd backend
ALLOWED_ORIGINS=http://192.168.1.142:8081 npm start
```
