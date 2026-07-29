# APK recovery: VietNam Map Checkin 1.0.14+21

This folder records facts recovered from:

`/home/thanhhao/thanhhao/Github/VietNam Map Checkin_1.apk`

The APK is a Flutter AOT release. Original Dart formatting, comments, local
variable names, and exact source statements cannot be reconstructed from
`libapp.so`. The files under `evidence/` preserve reproducible facts extracted
from the APK; reconstructed Dart and backend code in the repository is based on
those facts and the older Git source.

## Identity and upgrade compatibility

- Package: `com.example.vietnam_map_01`
- App label: `VietNam Map Checkin`
- Version: `1.0.14+21`
- minSdk: 24
- targetSdk / compileSdk: 36
- ABIs: Flutter AOT for `arm64-v8a`; datastore support libraries also exist for
  `armeabi-v7a` and `x86_64`
- Permissions: Internet, Camera, Request install packages
- Signing: APK Signature Scheme v2
- Signer certificate SHA-256:
  `8ce797953a677208a402556bc65aba74cf3b8db9f685fcb8d8153d18c44b5dbf`

Android preserves private data on an in-place update only when both the package
name and signing certificate match. Before installing a rebuilt APK over the
recovered APK, compare the signing certificate. A build signed by a different
debug key will require uninstalling the old app and will erase app-private data.

## Recovered persistent data

| Data | Location / key | Format |
| --- | --- | --- |
| Check-ins | SharedPreferences key `vnm_checkins` | JSON array |
| User name | SharedPreferences key `vmc-auth-user` | string |
| Password | SharedPreferences key `vmc-auth-password` | string |
| Backend URL | SharedPreferences key `vmc-backend-url` | string |
| Local photos | `/data/user/0/com.example.vietnam_map_01/files/vietnam_map_checkin_images` | image files grouped by province |
| Downloaded update | `/data/user/0/com.example.vietnam_map_01/cache/updates` | APK |

Check-in JSON schema:

```json
{
  "id": "stable UUID",
  "city": "province or city",
  "place": "display place",
  "notes": "free text",
  "source": "manual or gps",
  "synced": true,
  "createdAt": 1780386908045,
  "lat": 10.8231,
  "lng": 106.6297,
  "photo": "backend-relative path or URL",
  "localPhoto": "local:/absolute/private/path"
}
```

The APK ships an empty seed (`[]`). Real user data is not inside the APK; it is
stored in Android app-private storage or on the backend. The bundled GeoJSON is
byte-for-byte identical to the old source. `vn.svg` differs only by CRLF/LF line
endings.

## Recovered application flow

1. Startup loads theme, backend URL, and the locally cached account.
2. A first-time user registers; a returning user signs in. The APK also exposes
   forgot/reset password and account update flows.
3. After authentication the user chooses the VietNam Map Checkin workspace.
4. The map loads `assets/vietnam-provinces.geojson`, projects province polygons,
   and colors each province by check-in count.
5. Tapping a province opens its check-ins and the add-check-in action.
6. A check-in can use a gallery image or camera image. The image is copied to
   private storage first, then optionally uploaded to the backend.
7. The map and history screens support viewing, editing, replacing, and deleting
   a photo. Check-ins remain local-first when the backend is unavailable.
8. Two-way sync fetches remote items, pushes local-only IDs, merges by stable
   check-in ID, and orders by `createdAt`.
9. Settings manages account details, backend URL, local reset, and LAN APK
   update checks.

## Recovered backend contract

| Method | Route | Purpose |
| --- | --- | --- |
| POST | `/api/auth/register` | create account |
| POST | `/api/auth/login` | validate account |
| POST | `/api/auth/reset-password` | set a new password |
| POST | `/api/auth/update` | update name/password; APK includes `X-Password` |
| GET | `/api/checkins` | fetch all check-ins |
| POST | `/api/checkins` | create/update multipart check-in and photo |
| DELETE | `/api/checkins/:id` | delete check-in |
| DELETE | `/api/checkins/:id/photo` | delete only the photo |
| GET | `/api/update/latest` | obtain LAN update manifest |

The older backend did not contain auth or photo-only deletion. Compatible
implementations were reconstructed in `backend/server.js`. Account passwords
are stored with salted scrypt hashes in `backend/server-data/accounts.json`.

## Map behavior

- Source of truth: GeoJSON province polygons.
- Hit testing: projected polygon contains tap/hover point.
- Province association: normalized city text, with recovered
  `VietnamProvinceClassifier` support for point-in-polygon classification using
  latitude/longitude.
- Fill levels: 0, 1-2, 3-5, and 6+ check-ins.
- Tooltip: province name plus up to three recent photos.
- Detail: all province check-ins, add action, view/edit/delete actions.

## Recovery evidence

- `evidence/AndroidManifest.decoded.xml`: decoded binary manifest.
- `evidence/SHA256SUMS.txt`: APK and bundled asset hashes.
- `evidence/dart-aot-evidence.txt`: recovered Dart file paths, storage keys,
  routes, and application symbol names.
- `assets/App_VietNamMap_Logo_no_background.png`: exact logo extracted from the
  APK and restored to the source asset list.

Do not treat reconstructed code as a byte-identical source recovery. Treat this
document and evidence as the compatibility contract for future development and
data migration.
