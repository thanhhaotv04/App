# APK recovery record — Money Manager 1.0.8+9

## Identity and integrity

| Property | Recovered value |
|---|---|
| Source APK | `/home/thanhhao/thanhhao/Github/money_manager.apk` |
| SHA-256 | `717bc47366bfeb0f8cd31b395dc1f34549556ee2941e6b650c4a9515363d8139` |
| Android package | `com.thanhhao.money_manager` |
| Version | `1.0.8` (`versionCode` 9) |
| Minimum Android | API 24 |
| Target/compile Android | API 36 |
| APK ABIs | `arm64-v8a`, `armeabi-v7a`, `x86_64` |
| Flutter/Dart snapshot | Dart 3.12.1, `ace654289f5abc240509fc941453ebc5` |
| Signing certificate SHA-256 | `8ce797953a677208a402556bc65aba74cf3b8db9f685fcb8d8153d18c44b5dbf` |
| APK signature scheme | v2 |

The embedded UI still contains the stale strings `Current 1.0.4+5` and
`Already up to date: 1.0.4+5`; Android package metadata is authoritative and
reports 1.0.8+9.

The APK contains a single app source library,
`package:money_manager/main.dart`. Its recorded build path was
`D:/thanhhao_ws/App/App_VietNam_Map_Flutter/money-manager/`.

## Critical signing and data warning

No matching private signing key was found during recovery. A private key cannot
be derived from the APK certificate. An APK signed with a different key:

- cannot be installed as an update over the original app;
- requires uninstalling the original app first; and
- therefore causes Android to remove the original app's private local data.

Keep the original installation and APK untouched. Before trying a replacement,
use the original app's sync function against the recovered backend and verify
the server copy. If a matching `.jks`/`.keystore` is later found, confirm that
its certificate SHA-256 exactly matches the value above.

## Runtime flow

```text
Launch
  -> load SharedPreferences
  -> apply every due recurring expense
  -> load cached vmc-auth-user/vmc-auth-password
       -> absent: Sign in / Register / Reset password
       -> present: Overview / Add / History / Account

Add transaction
  -> create stable UUID transaction
  -> save JSON to money-manager-transactions-v2

Sync now
  -> login to backend (register automatically only when account is absent)
  -> GET remote money data
  -> merge local and remote by stable id
  -> POST merged result to backend
  -> save the same merged result locally

Check update
  -> GET update manifest
  -> download newer APK to cache/updates
  -> Android FileProvider
  -> ACTION_VIEW package installer
```

## Local storage map

SharedPreferences values are JSON strings unless noted otherwise.

| Key | Purpose |
|---|---|
| `money-manager-transactions-v2` | Current transaction list |
| `money-manager-transactions-v1` | Legacy transaction fallback |
| `money-manager-recurring-v1` | Recurring expense rules |
| `money-manager-backend-url` | Backend base URL, default `http://127.0.0.1:3000` |
| `vmc-auth-user` | Cached user name |
| `vmc-auth-password` | Cached password |

Trailing `/` characters are removed from the backend URL.

### Transaction JSON

```json
{
  "id": "stable-string-id",
  "title": "Lunch",
  "note": "Office meal",
  "category": "Food",
  "amount": 65000,
  "date": "2026-07-29T10:00:00.000",
  "type": "expense",
  "icon": 62230
}
```

- `type`: `income` or `expense`; missing/unknown values become `expense`.
- `note` defaults to an empty string.
- `icon` defaults to decimal `62191` (`0xf2ef`).
- `amount` is an integer.
- `date` is ISO-8601.

### Recurring expense JSON

```json
{
  "id": "stable-string-id",
  "title": "Rent",
  "amount": 5000000,
  "category": "Monthly",
  "frequency": "monthly",
  "dayOfMonth": 1,
  "lastAppliedAt": "2026-07-01T00:00:00.000",
  "active": true
}
```

- `frequency`: `daily` or `monthly`; missing/unknown values become `daily`.
- `dayOfMonth` defaults to 1.
- `active` defaults to true.
- Monthly dates are clamped to the last valid day of the month.
- Generated transaction notes are `Daily recurring expense` or
  `Monthly recurring expense`.

## Category map

| Name | Material icon code point |
|---|---:|
| Income | `0xf266` |
| Monthly | `0xf051f` |
| Daily | `0xf44d` |
| Fun | `0xf1f5` |
| Bills | `0xf2ef` |
| Shopping | `0xf37d` |
| Food | `0xf316` |

The original seed data recovered from AOT assembly is:

| ID | Title | Note | Category | Amount | Relative time |
|---|---|---|---|---:|---|
| `seed-1` | Lunch | Office meal | Food | 65,000 | now - 3 hours |
| `seed-2` | Groceries | Household items | Shopping | 385,000 | now - 7 hours |
| `seed-3` | Movie | Weekend | Fun | 90,000 | now - 1 day |

## Backend API map

| Method | Path | Purpose |
|---|---|---|
| POST | `/api/auth/login` | Sign in |
| POST | `/api/auth/register` | Create account |
| POST | `/api/auth/reset-password` | Reset password |
| POST | `/api/auth/update` | Change password/account data |
| GET | `/api/money-manager/data` | Pull user data |
| POST | `/api/money-manager/data` | Save user data |
| GET | `/api/update/latest` | Fetch update manifest |

Sync requests use `X-User-Name` and `X-Password`. POST bodies use
`Content-Type: application/json`. The money payload is:

```json
{
  "transactions": [],
  "recurring": []
}
```

Transactions are merged by `id`; if both sides contain the ID, the later
`date` wins. Recurring rules are merged by `id`; the later `lastAppliedAt`
wins. Transactions are sorted newest first. A `401` is treated as an account
credential error.

## Android integration

- Permissions: `INTERNET`, `REQUEST_INSTALL_PACKAGES`.
- Cleartext HTTP is enabled for local/LAN backend use.
- Flutter method channel: `money_manager/update`.
- Method: `installApk`, argument `{ "path": "/absolute/path.apk" }`.
- FileProvider authority: `com.thanhhao.money_manager.fileprovider`.
- Shared cache directory: `updates/`.
- APK MIME type: `application/vnd.android.package-archive`.

## Screen and function inventory

- Authentication: sign in, register, password reset, backend URL.
- Overview: totals/statistics and recent transactions.
- Add: expense/income, title, amount, category, optional recurring rule.
- Recurring: daily/monthly schedule, active state, remove rule.
- History: list, search/filter, remove transaction.
- Account: backend configuration, two-way sync, update install, password
  change, clear today's data, clear current month's data, sign out.
- Theme: light/dark toggle.

Recovered class/method names include `MoneyStore`, `AuthService`,
`MoneySyncService`, `AppUpdateService`, `Tx`, `RecurringExpense`,
`MoneyCategory`, `AuthScreen`, `HomeScreen`, `OverviewPage`,
`AddExpensePage`, `HistoryPage`, `AccountPage`, `TransactionTile`,
`RecurringTile`, `SummaryPanel`, `EntryPanel`, `Keypad`, and overview
statistics/grid widgets.

## Retained evidence

The `evidence/` directory retains:

- decoded Android manifest and FileProvider paths;
- Blutter's arm64 Dart AOT assembly for the app library;
- Dart object and constant-pool inventories used to recover exact strings,
  constants, class names, fields and method names.

These are analysis artifacts, not compilable Dart source. The maintained,
readable reconstruction lives under the project's `lib/` directory.

## Recovery confidence and limitations

High confidence: package/version, signing certificate, permissions, storage
keys, JSON field names/defaults, URLs, headers, merge rules, categories, seed
data, method channel, feature and class inventory.

Reimplemented rather than byte-for-byte recovered: widget layout details,
theme colors, some animation/presentation behavior, and backend internals. Dart
AOT does not preserve the original source text, comments, local variable names,
or exact file formatting.

No geographic map feature or map SDK was present in this APK. “Map” in this
record refers to the data/API/function mapping.
