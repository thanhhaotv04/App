# Security and UX validation — 2026-10-09

Scope: review and complete the existing Task Reminder privacy, account isolation,
secure-session, deletion-sync, update-integrity and UX changes. Source delivery uses
the existing `Task-Reminder` branch. No production data was modified; no release,
version bump or persistent backend deployment is part of this change.

## Fixed findings

| Area | Change |
| --- | --- |
| Offline login | Reject incorrect passwords; keep salted verifiers after logout; preserve legacy sign-in and existing sessions. |
| Credentials | Migrate plaintext preferences into platform secure storage; no plaintext fallback if secure storage fails; bind bearer tokens to account and backend. |
| Account isolation | Scope local tasks/schedules by normalized username hash; migrate only the recorded legacy owner's data and retain the originals. Server data remains scoped by account ID. |
| Server authentication | Hashed, expiring bearer sessions; logout revocation; password change verifies the old password and revokes other sessions; disable unauthenticated password reset. |
| API hardening | Persistent IP rate limits, exact CORS allowlist, payload/record limits, strict dates and numeric ranges, duplicate-ID/orphan rejection, production TLS guard and non-sensitive errors. |
| Persistence and sync | Serialize server read-modify-write operations with atomic JSON replacement; preserve corrupt files instead of resetting; merge record IDs and retain deletion tombstones against stale devices. |
| Update delivery | Read the installed build number, disallow redirects/cross-origin APK URLs, bound downloads, verify size/SHA-256, and check cached APK package/version before installation. |
| Notifications | Explicit opt-in, stable IDs, future/pending reminders only, serialized scheduling/cancellation, Android boot/update receivers, cancel on sign-out. |
| User experience | Visible/recoverable async errors, password visibility controls, undo schedule removal, duplicate-title protection, bounded fields, and whole-token Quick Add parsing (e.g. “email” no longer means “mai”). |
| Dependency | Update the vulnerable transitive Node `qs` dependency; add secure storage and installed-package metadata support to Flutter. |
| Offline authentication | Match the VietNam-map-checkin Sign in/Register flow, add password confirmation, keep Backend URL out of authentication, and upgrade local PBKDF2 verifiers to 600,000 iterations after a successful legacy login. |
| Network transport | Require HTTPS for every non-loopback backend and disable Android cleartext traffic. Login and registration remain fully local/offline. |
| Abuse resistance | Return one generic login failure, isolate auth limits by IP and account, avoid disk writes for already-blocked requests, and upgrade server password hashes to OWASP-minimum scrypt parameters with legacy rehash. |
| Session revocation | Queue the original backend/token pair in secure storage before local sign-out and retry revocation without blocking offline use. |
| Notification privacy | Hide task titles by default on every platform; allow explicit opt-in to show titles; mark Android notifications private and provide a switch to disable/cancel reminders. |
| Credential migration | Remove stale plaintext/fallback password and token copies, including interrupted migrations and orphaned signed-out credentials. |
| API cache privacy | Apply `Cache-Control: no-store` to API responses regardless of path casing, including unauthorized requests. |
| Server consent and recovery | Confirm the destination before first sync or a server change. Refresh a changed password only after explicit server sign-in against the account's previously linked origin. |
| Settings and accessibility | Group sync and preferences, show progress and live status by the active action, use clear password labels/autofill, and allow library cards and status pills to grow for large text. |
| Dependency refresh | Recheck on 2026-10-09 and patch `proxy-addr` to 2.0.8. The audited tree reports no known vulnerabilities. The app disables proxy trust; the advisory's subnet misconfiguration is not enabled here. |

## Validation evidence

- `flutter analyze --no-pub`: no issues.
- `flutter test --coverage --concurrency=1`: **67 passed**; line coverage **2306/2852 (80.9%)**.
- `npm test` in `backend/`: **11 passed**, using isolated temporary data and release fixtures.
- `npm audit --audit-level=moderate`: **0 reported vulnerabilities** for the installed Node dependency tree at validation time. This is not a full application security certification or a Dart vulnerability audit.
- Gitleaks v8.30.1: **0 findings** in the branch's complete Git history and the staged publication diff; credentials/signing material and runtime data are ignored by Git. Automated secret detection does not prove the absence of every kind of personal information.
- `node --check backend/server.js`, `bash -n fastUpdate.sh`, `git diff --check`: passed.
- `flutter build web --no-pub`: passed.
- `flutter build apk --debug --no-pub`: passed. `aapt` confirms
  `com.thanhhao.task_reminder`, version **1.0.6+7**, minSdk 24, targetSdk 36.
  `apksigner verify` passed for this debug artifact; it is not a release-signing check.
- Merged Android manifest contains non-exported reminder receivers, boot permission,
  disabled application backup and `usesCleartextTraffic="false"`. FileProvider
  remains non-exported.
- Responsive widget checks cover 375/768/1024/1440 widths, phone-scale dialogs,
  200% text and portrait/landscape layouts with long task titles and notes.
  Account and offline registration previews were rendered to ignored
  `build/review/account.png` and `build/review/auth.png` for inspection; they are
  test renderings, not physical-device screenshots.

The Android toolchain emits native-access/SDK-tool compatibility warnings, but
the debug build succeeds. Build output and coverage remain ignored by Git.

## Deployment and remaining checks

1. **Back up before rollout and deploy matching client/backend code.** Old clients
   using password headers are no longer accepted.
   Do not reset or delete existing account/task files. Unowned legacy local data
   requires explicit recovery rather than assigning it to another account.
2. **Use HTTPS.** Non-loopback HTTP is rejected and Android cleartext is disabled.
   Browser credential storage requires HTTPS or localhost. The APK hash protects
   integrity against the supplied manifest, not against an attacker who controls
   both an HTTP manifest and APK.
3. **Single backend process per data directory.** JSON files and in-process locking
   are not suitable for multi-process replicas. Local preferences are not an
   encrypted task vault or a crash-atomic multi-key database. Keep recoverable backups.
4. **Bounded local-first sync.** Record conflict resolution uses device timestamps;
   keep clocks correct. Tombstones count toward quotas and are intentionally not
   discarded automatically, since stale devices may return. Logout revocation is
   queued and retried when offline; server sessions also expire after 30 days.
5. **Physical testing remains necessary.** `flutter devices` detected an Android 16
   phone and Linux. Physical acceptance of this new build remains pending: verify
   notification permission denial/grant, reboot, Doze/battery
   restrictions, timezone changes, actual multi-device use, OS secure storage and
   in-place APK installation with the existing release certificate. Only the next
   64 future reminders are queued; reopening the app refreshes that window.
   iOS/macOS/Linux native builds and real-browser end-to-end runs were not validated.

These checks address the confirmed findings and regressions in scope. They do
not establish that every possible bug or user annoyance has been eliminated.

## Reference documentation

- [Flutter secure storage setup and web restrictions](https://pub.dev/packages/flutter_secure_storage)
- [Local notification platform setup](https://pub.dev/packages/flutter_local_notifications/versions/19.5.0)
- [Android package archive inspection](https://developer.android.com/reference/android/content/pm/PackageManager)
- [Installed package version metadata](https://developer.android.com/reference/android/content/pm/PackageInfo)
- [Android notification privacy](https://developer.android.com/develop/ui/compose/notifications/create-notification)
- [OWASP password storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [proxy-addr security advisory](https://github.com/advisories/GHSA-jqcg-44mw-7w3h)
