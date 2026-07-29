# Money Manager — recovered source

This project was reconstructed from `../../money_manager.apk` after the newest
source was lost. It preserves the APK's package name, local storage keys, JSON
models, authentication endpoints, sync protocol, update channel, and core app
flows.

> Do not uninstall the original app from a device that still contains valuable
> data. The recovered source is compatible with its data format, but a newly
> built APK cannot update the original installation unless it is signed with
> the original signing key.

## What is available

- Flutter app: sign in/register/reset, overview, income/expense entry, daily
  and monthly recurring expenses, history/search/delete, account settings,
  two-way sync, password change, update check and APK install.
- Compatible local backend in [`backend/`](backend/).
- Reverse-engineering notes, schemas, flow map and retained evidence in
  [`recovery/apk-1.0.8+9/`](recovery/apk-1.0.8+9/).

## Run the app

```bash
flutter pub get
flutter run
```

Android emulator reaches a backend on the host with
`http://10.0.2.2:3000`. A physical phone must use the computer's LAN address,
for example `http://192.168.1.10:3000`.

## Run the sync backend

```bash
cd backend
npm install
npm start
```

Runtime account and money data are written under `backend/server-data/`, which
is intentionally ignored by Git. Back that directory up separately.

To publish an update, place the APK in `backend/releases/` and update
`backend/releases/latest.json`. The next version must have a `versionCode`
greater than `9`.

## Validate

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

See the recovery notes before building or installing a release.

Release signing is intentionally disabled in Gradle until the original key is
recovered. The debug APK is only for a separate test device/profile; it cannot
replace the APK already installed under the original signature.
