# Hướng dẫn sử dụng và phát triển

[Xem giới thiệu và ảnh giao diện](../README.md). Các lệnh chạy từ thư mục gốc dự án, trừ đoạn có `cd backend`.

Máy phát triển cần Flutter với Dart tương thích `pubspec.yaml`, Android SDK để build APK và Node.js/npm để chạy backend.

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
  - `task-reminder-tasks-v1:<account hash>`
  - `task-reminder-assignments-v1:<account hash>`
  - `task-reminder-backend-url`
  - `task-reminder-auth-user`
  - Password and bearer session: platform secure storage, not plaintext preferences.
  - Salted password verifier for offline sign-in; sign-out keeps the account's tasks.
  - Legacy unscoped task keys are retained as migration backups and copied only
    for their known owner. Unowned legacy data is not assigned to a new account.
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
npm ci
ALLOWED_ORIGINS=http://localhost:8081 npm start
```

Start the web preview:

```bash
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8081
```

Open:

```text
http://localhost:8081
```

Backend URL for local desktop/web development:

```text
http://127.0.0.1:3002
```

The Backend URL is only needed in the Account tab when syncing data or checking
updates.

Secure storage on the web requires HTTPS or localhost; a plain HTTP LAN browser
preview cannot save credentials. Native Android and every non-loopback backend
must use HTTPS; cleartext Android traffic is disabled. Signing in, registering,
changing an offline-only password, and managing local tasks never require a
backend. The app connects only after the user explicitly chooses Sync, Check
update, or Sign in with server password. The first Sync to a new server asks for
confirmation before sending credentials and tasks.

## Security and migration

- Back up `backend/server-data/` before deploying the new backend. Use one Node
  process per `DATA_DIR`; JSON locking is process-local, not a clustered database.
- Upgrade client and backend together. Sync now uses bearer tokens (30-day
  lifetime, at most 10 sessions/account). Password-header authentication has been
  removed. Public password reset is disabled unconditionally.
- Create account establishes a local account. The first explicit Sync signs in
  to the backend or registers the account if it does not exist. Existing server
  accounts require the correct password; offline account creation is not proof of
  ownership of a server account.
- A successfully synced account keeps its backend binding after sign-out. Pending
  server-session revocation is retained securely and retried when connectivity
  returns. Change its password while that backend is reachable. After a password
  change on another device, sign out, enter the new password and choose
  **Sign in with server password** after a failed local sign-in. This requires
  connectivity and uses the previously linked server to refresh the local verifier;
  editing Backend URL cannot redirect recovery credentials. Offline-only accounts
  can change passwords without a backend.
- Deleted records remain as sync tombstones. Merge preserves IDs and concurrent
  records; parent deletion wins over stale edits. Limits: 1000 tasks, 5000 schedules
  per account including tombstones, and 1 MiB per request. Keep device clocks correct.
- Malformed saved JSON reports an error and is not silently reset. Keep backups;
  local preferences are not a transactional database or an encrypted task vault.
- Enable **Task reminders** explicitly in Account; switch it off to cancel reminders.
  Task titles are hidden in notifications by default. **Show task titles** is an
  optional setting; Android marks notifications private on the lock screen.
  Only future, pending reminders are scheduled (up to the next 64); past reminders
  are not replayed on app launch.
  Android uses inexact alarms, so delivery time depends on OS battery policies.
- APK downloads must stay on the configured backend origin, match size and SHA-256,
  and pass Android package/version checks. Android still verifies update signing.
  Keep the existing release certificate; hashes over HTTP do not prevent a network
  attacker from replacing both the APK and its manifest. Use HTTPS for deployment.
- TLS can terminate in Node using `TLS_CERT_FILE` and `TLS_KEY_FILE`, or at a trusted
  reverse proxy with `TLS_TERMINATED_BY_PROXY=1`. `NODE_ENV=production` refuses to
  start without either. Bind to loopback behind the proxy and set `ALLOWED_ORIGINS`
  to exact web origins. Login failures use the same response for missing accounts
  and wrong passwords. Authentication limits are separated by IP and account;
  the general API limit remains per process because this JSON backend supports a
  single process only.
- `fastUpdate.sh --serve` binds to loopback over HTTP by default. Supplying both
  TLS files switches it to LAN HTTPS; it no longer exposes a cleartext LAN backend.

See [SECURITY_REVIEW.md](../SECURITY_REVIEW.md) for validation and remaining device checks.

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

Only prepare or publish an APK release when a release is requested. Documentation
changes and GitHub pushes do not require a version bump.

Use the user-facing label `YYMMDD.N` in `Asia/Ho_Chi_Minh`, starting at `.1` each
day. Keep Android `versionCode` strictly greater than the installed and previously
published builds. Flutter's three-part version field can represent that label as
`YYMMDD.N.0+<versionCode>`; the Android build and update manifest must use the
agreed user-visible label and the same build number.

The current `fastUpdate.sh` defaults to bumping a three-part semantic version and
rejects a two-part `YYMMDD.N` in `VERSION_NAME`. It does not implement the date-based
release convention. Use the explicit build workflow below for a date-labelled
release, after setting `TASK_RELEASE_LABEL` and `TASK_BUILD_CODE` to the agreed
label and an increasing integer, and updating `pubspec.yaml` consistently:

```bash
flutter build apk --release \
  --build-name="$TASK_RELEASE_LABEL" --build-number="$TASK_BUILD_CODE"
cp build/app/outputs/flutter-apk/app-release.apk \
  build/app/outputs/flutter-apk/app-release-task-reminder.apk
cp build/app/outputs/flutter-apk/app-release-task-reminder.apk \
  backend/releases/app-release-task-reminder.apk
```

Before making the update available:

1. Keep `com.thanhhao.task_reminder` and the existing release signing certificate.
   Configure the signing key through the project's Android signing settings.
2. Verify the package, versionName, versionCode and signing certificate inside the
   built APK; use those exact values in `backend/releases/latest.json` together
   with `apkFile: app-release-task-reminder.apk` and release notes.
3. Back up `backend/server-data/`, then run the matching backend. For LAN access,
   configure both TLS files and bind to a reachable interface:

```bash
cd backend
npm ci
HOST=0.0.0.0 \
TLS_CERT_FILE=/path/fullchain.pem TLS_KEY_FILE=/path/private-key.pem \
npm start
```

4. Set the app's Backend URL to `https://<YOUR-HOST>:3002` and select
   **Account → Check update**. The backend adds the current APK's size and SHA-256
   to `/api/update/latest`; the app validates these before Android installation.
   Browser users also need their exact HTTPS origin in `ALLOWED_ORIGINS`.

Keep the published manifest and APK together. Starting the backend alone does
not build an APK, and changing only `latest.json` does not change the version
inside an existing APK.
