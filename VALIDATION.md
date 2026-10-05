# Local validation

## App reliability fixes — 2026-10-04 (local, not deployed)

- Fixed the six issues from the app audit: BLE write rejection/exception or
  missing callback now reconnects while retaining the pending command; Wi-Fi
  health polls without locking controls and failed sends clear stale status;
  old health responses cannot overwrite a newer send failure.
- Storage recovers valid records independently and preserves the original
  snapshot in a timestamped SharedPreferences recovery key before writing the
  repaired snapshot. Unreadable JSON fails visibly and cannot be overwritten
  by a subsequent normal save. The app shows a recovery warning when needed.
- Bluetooth content that exceeds the packet limit now requires confirmation
  of the exact shortened text, or Cancel. Original saved content is unchanged.
  Retry connection catches native errors, displays feedback and clears busy state.
- A retry of APK installation reuses a cached file only after verifying its
  size, SHA-256 and ZIP header. A modified cache is downloaded again; native
  package/version/signature checks remain in place. Returning from permission
  settings still requires retrying the update action, but not downloading again.
- Checks: Flutter analyze clean; 43 Flutter tests passed, including seven new
  regression cases; 23 Android JVM tests passed (19 existing plus four new BLE
  recovery tests); backend `npm test` passed (one integration test).
- Flutter line coverage: 1,043/1,344 lines (77.6%). Long-message confirmation
  tested at width 375 with text scale 1.6; existing responsive layout tests pass.
- `flutter build web --no-pub` and Gradle `:app:assembleDebug` passed. Local
  debug APK: `App/build/app/outputs/apk/debug/app-debug.apk`. Mockito and its
  JDK-compatible instrumentation dependencies are test-only.
- No APK installed, no firmware changed/flashed in this fix session, no update
  manifest published, no version/package ID changed. BLE failures were injected
  in JVM tests, not reproduced on the physical phone/ESP32. Long-running riding,
  Doze and physical TFT behavior still require a stationary on-device test.

## Firmware validation — 2026-10-03

## Clock menu: background Stopwatch and Timer — firmware 1.3.17

- Added `Clock → Stopwatch / Timer` to the physical-button menu. Stopwatch
  has Start/Pause/Resume/Reset; leaving its page keeps it running. Timer has
  5/15/30/60-minute presets, an `At time` 24-hour editor and `View timer` /
  Cancel. Selecting a clock time schedules its next occurrence, including
  tomorrow when the selected time has passed. Only this clock-time entry
  requires a synchronized wall clock.
- Both counters use ESP32's 64-bit monotonic timer and operate concurrently,
  without Wi-Fi/BLE or dependence on later wall-clock synchronization.
  Active counters use small bottom-right minute labels (`SW`, `T`, optional
  `P` for paused stopwatch). Road text remains size 2 and was moved above
  the reserved footer; its page indicators are at the bottom left.
- Timer expiry changes the full screen between black and white every 700 ms
  with `TIME UP`. Any released button dismisses it and is consumed before
  normal quick-mode/menu handling. The saved theme is not changed, and the
  stopwatch continues while the alarm is visible. State is RAM-only and
  resets on reboot/power loss.
- Host C++ assertions passed for concurrent operation, start/pause/resume,
  reset/cancel, every duration preset, one-shot expiry, minute rounding,
  midnight/next-day scheduling and operation across the 32-bit millisecond
  boundary. The test uses the same `include/clock_timers.h` as firmware.
- PlatformIO build and USB flash of 1.3.17 passed on ESP32-S3
  `14:C1:9F:27:03:44`; uploaded image hash verified. RAM: 52,356 bytes;
  program size: 1,028,533 bytes. The user started Stopwatch and a 300-second
  Timer through the physical buttons, then confirmed both minute labels
  were clear. The device reported 1.3.17 through `/api/health`; a live HTTP
  roundabout sample (`EXIT 4`, `Nguyen Hue`, 250 m) was accepted and logged
  while the counters ran. The full real 5-minute countdown subsequently
  logged `CLOCK: timer expired`, followed by button dismissal, navigation
  restoration and `CLOCK: alarm dismissed; theme restored`. The user also
  confirmed the continuous black/white alarm, return to navigation after
  dismissal, and continued stopwatch minute count all worked correctly.

## QR menu: Bank and Profile — firmware 1.3.16

- Added `Menu → QR → Bank / Profile` using the two user-supplied images.
  Decoded each original QR and re-encoded its exact payload without logos.
  The Bank payload identifies TPBank account 70333655343; Profile preserves
  the original `https://q.me-qr.com/2rw76u3u` URL.
- Host generation uses QR error correction M, integer module scaling and
  a four-module white quiet zone. Bank is 45 modules at 2 px/module (106 px
  including the quiet zone); Profile is 29 modules at 3 px/module (111 px).
  Both reconstructed 128×160 raster images decode to the exact original
  contents using ZXing. Packed bitmap verification and regenerated-header
  comparison passed. No runtime QR library or network request is required.
- Main menu now has five rows; QR submenu has two. Button 1 moves to the
  next item/code, Button 2 opens the selected item, and Button 3 goes back.
  QR pages have no inactivity timeout or timed redraw. Navigation updates
  continue behind the menu, and normal navigation is restored on menu exit.
- PlatformIO build and USB upload of 1.3.16 passed on ESP32-S3
  `14:C1:9F:27:03:44`, with flash hash verification. RAM usage is 52,252 bytes;
  program size is 1,022,225 bytes. Physical menu/phone-scan confirmation is
  pending from the user; successful host decoding is not a camera scan of
  the actual TFT.

## OsmAnd turn icons and stable roundabout rendering — firmware 1.3.15

- Compared OsmAnd's `TurnType.java`, `TurnPathHelper.java`, `TurnDrawable.java`,
  and `ExternalApiHelper.java` from `osmandapp/OsmAnd` master. The 14 primary
  turn codes are C, TL, TSLL, TSHL, TR, TSLR, TSHR, KL, KR, TU, TRU,
  OFFR, RNDB and RNLB. The Android bridge and TFT now retain distinct types
  for each instead of collapsing slight/sharp/keep and right U-turn.
- Root cause of the old/new roundabout swap: AIDL snapshots carry the real
  exit angle, while the notification and bare direction callback do not.
  The listener now refreshes an available complete AIDL snapshot before using
  notification fallback; a bare callback no longer marks itself as a complete
  snapshot. Firmware removed the separate solid-circle fallback and always
  renders the same ring/path design. Missing angles use OsmAnd TurnType's
  default angle 0, so the exit direction is only approximate in that case.
- PlatformIO build and upload of 1.3.15 passed on the connected ESP32-S3
  (`14:C1:9F:27:03:44`); flash hash verified. Flutter analyzer passed,
  all 36 Flutter tests passed, and all 19 local Android bridge tests passed.
  Release APK built and installed into personal user 0. Work-profile user 11
  remains uninstalled.
- On the phone, notification listener and OsmAnd AIDL connected, then BLE
  negotiated MTU 185 without changing notification permission. The app sent
  `sharp_left` and roundabout samples. Firmware serial confirmed
  `sharp_left Nguyen Hue 250 m`, followed by roundabout exits 5 and 4 with
  angles -115 and -100; Android logged firmware ACKs. A mistaken screen tap
  briefly selected EXIT 5 during verification because the expanded sample
  list had scrolled after the prior tap; re-reading the fresh UI coordinates
  and selecting EXIT 4 produced the matching firmware log and ACK. The user
  confirmed EXIT 4 and the new roundabout glyph were clear on the TFT.
- Live OsmAnd route geometry was not simulated in this run. Only the complete AIDL
  snapshot can provide a real exit angle; notification-only fallback remains
  an approximate route cue.

## Compact navigation, exits 4–6 and connection recovery — firmware 1.3.14

- Clock/date/status now occupy the top 40 of 160 TFT rows. Navigation uses
  the remaining 120 rows, with an exit/direction label and full-width road
  names at text size 2. Long road names wrap and page every 3.5 seconds;
  only the affected display regions redraw. Road names retain the existing
  ASCII transliteration for the TFT font.
- Added app samples for roundabout exits 4, 5 and 6 and support for five dim
  passed-exit ticks. The final exit direction uses OsmAnd's actual angle;
  intermediate dim ticks and sample angles are illustrative, not mapped
  road geometry. Parser tests cover exits 1–6 without deriving angles from
  the exit number, and check the 180-byte packet limit.
- Flutter analyzer passed; all 36 Flutter tests and 17 Android unit tests
  passed. Release APK build and OsmAnd release parcelable check passed.
  PlatformIO built and flashed firmware 1.3.14 to ESP32-S3
  `14:C1:9F:27:03:44`, with flash hash verification.
- The locally built APK was installed explicitly into personal user 0.
  BLE samples for exits 4, 5 and 6 received firmware acknowledgements;
  serial logs recorded `DISPLAY: navigation roundabout Nguyen Hue 250 m`
  with exit/angle pairs `4/-100`, `5/-115` and `6/-125`.
  On-glass readability of the new layout still awaits user confirmation.
- Notification access is checked for the exact listener component. App
  resume/Retry connection first requests a rebind; if Android retains a
  stale binding, the app restarts only its listener component without
  changing the user's notification-access grant. Recovery is throttled.
  A live force-stop/reopen test logged stale-binding repair at 16:24:26,
  listener and OsmAnd AIDL connection at 16:24:27, and BLE connection/MTU
  negotiation at 16:24:28. Notification access remained granted throughout;
  no manual permission toggle was used. The idle route cleared directions.
- The duplicate icon came from the same package being installed in both
  personal user 0 and work-profile user 11. Removed only the work-profile
  installation with `pm uninstall -k --user 11`; its data was retained for
  recovery. Verified user 0 installed=true and user 11 installed=false.
  Subsequent USB installation used `adb install --user 0 -r`.
- APK version remains 261001.4.0 (26100104) for this local validation.
  The update backend's published release was not changed.

## Roundabout circulation direction — 2026-10-03

- The user confirmed the `1.3.7` arrow was easier to see but appeared to turn
  the wrong way. Firmware `1.3.8` moves the large accent arrowhead to the top
  of the ring: leftward for counterclockwise `roundabout`, rightward for the
  opposite `roundabout_left`. The smaller centered exit number is unchanged.
- PlatformIO compiled and flashed `1.3.8` to ESP32-S3
  `14:C1:9F:27:03:44` with verified flash hash. After the reset Android again
  showed `Ready for directions` / `Connected · Bluetooth`, and its Roundabout
  sample received a firmware ACK. The user is checking the new on-glass arrow.

## Roundabout contrast and label size — 2026-10-03

- The user reported that the `1.3.6` arrowhead blended into the white ring and
  the one-digit exit number was too large. Firmware `1.3.7` keeps the ring's
  size, draws a wider arrowhead in the accent color on top of the ring, and
  centers both one- and two-digit labels at text size 2.
- PlatformIO compiled and flashed `1.3.7` to ESP32-S3
  `14:C1:9F:27:03:44` with verified flash hash. After reset, the app returned
  to `Ready for directions` / `Connected · Bluetooth`; the Roundabout sample
  received a firmware ACK. The user's visual confirmation is pending.

## Roundabout arrow and centered exit number — 2026-10-03

- User feedback on the flashed `1.3.5` glyph requested a number centered in
  the circle and an arrowhead on the ring. Firmware `1.3.6` centers the ring
  in its 54x66 dirty region, draws a larger one-digit ordinal (two digits use
  a smaller font), and joins an upward arrowhead to the ring. The arrowhead is
  mirrored for `roundabout_left`.
- PlatformIO compiled and flashed `1.3.6` to ESP32-S3
  `14:C1:9F:27:03:44` with verified flash hash. The phone reconnected over
  BLE; app status returned to `Ready for directions` and `Connected · Bluetooth`.
  Sending the Roundabout sample produced the app's firmware ACK and serial
  `DISPLAY: navigation roundabout Nguyen Hue 250 m exit=2`.
- The user's on-glass visual confirmation of this newest glyph is pending.

## TFT maneuver geometry from device photos — 2026-10-03

- The user's TFT photos showed a thin roundabout with a long entry stem, a
  U-turn arrowhead on the right, and left/right arrows without an approach
  segment. Firmware `1.3.5` changes the ring to a large stemless circle with
  a centered exit ordinal, mirrors the U-turn to point down the left lane,
  and gives left/right turns a vertical approach and 90-degree bend.
- All glyph pixels stay within the arrow dirty region `(4,82,54,66)`, including
  the 500 ms blink clear. No full-screen redraw was introduced.
- PlatformIO compiled and flashed `1.3.5` to ESP32-S3
  `14:C1:9F:27:03:44`; esptool verified the flash hash. The Android app
  reconnected over BLE and again showed `Ready for directions`.
- From the existing app Test display panel, the 250 m Left, Right, U-turn and
  Roundabout samples each received a firmware ACK. Serial logs recorded all
  four maneuvers and `exit=2` for the roundabout. The on-glass appearance of
  the new glyphs still needs visual confirmation from the user; serial logs
  only establish that the renderer was called.

## BLE reconnect and maneuver icon refinement — 2026-10-03

- Refined the roundabout glyph into a joined approach lane and thick ring with
  a tangent circulation arrow. Kept every pixel within the arrow's blink/clear
  rectangle, so the hidden phase cannot leave a stray line. Added a “Roundabout”
  sample button in the app's existing Test display section (exit 2).
- Android now queues initial commands while MTU negotiation is in progress,
  but marks the BLE channel ready only after MTU >= 183 (the 180-byte packet
  plus ATT header). A rejected/too-small MTU closes and retries the GATT link;
  it no longer reports a connected-but-unusable channel. Actual negotiated MTU
  is used to reject writes that cannot fit.
- Preserved bounded exponential reconnect, interrupted-command replay, active
  OsmAnd direction replay after notification subscription, 15-second GATT setup
  timeout, and the foreground retry path. Added concise connection/MTU logs.
- A first on-device pass exposed an ordering bug in the stricter MTU check:
  startup commands were rejected before GATT began connecting. Fixed by applying
  the strict negotiated-MTU limit only once the channel is ready; initial
  commands are queued under the configured 185-byte limit.
- Identified Android notification-listener service loss as a separate failure
  mode: the OS had marked notification access enabled while the listener was
  no longer running. Added a delayed `requestRebind` recovery and connection
  lifecycle logs.
- Flutter analyzer clean; **36 Flutter tests** and **16 Kotlin tests** passed.
  PlatformIO build and release APK build passed; OsmAnd R8 check passed.
- Installed the release APK in place (applicationId/data retained) and flashed
  firmware `1.3.4` to ESP32-S3 `14:C1:9F:27:03:44`; flash hash verification
  succeeded. After a forced firmware reset, Android reconnected, negotiated MTU
  185, and returned to `Ready for directions` / `Connected · Bluetooth`.
- Sent the app's roundabout sample over BLE after reconnect. Firmware serial
  confirmed `DISPLAY: navigation roundabout Nguyen Hue 250 m exit=2` and the app
  displayed “ESP32 received the 250 m navigation sample.” This confirms packet,
  ACK and renderer path; TFT glass appearance still needs the user's visual
  confirmation (no camera/photo is attached to the device).
- Latest local artifacts: APK SHA-256
  `a09b44b96958551dd84c3ee1051bc392d973cb07243d3bb8ff8a707aa8d583a3`; firmware
  SHA-256 `3c62ea36236e60d24b11c66bbaab3d0c6edf197fd7f9ff1e2a0ed18611bb15c0`.
  APK was installed in place; no public update server was changed. No OsmAnd
  route simulation was run.

## Maneuver icons — 2026-10-03

- Updated the TFT U-turn to a curved return arrow and the roundabout to a ring
  with a circulation arrow; an OsmAnd exit ordinal is shown in the ring when
  supplied. The renderer does not infer an exit path from the ordinal.
- Kept the existing <2 km visibility, <1 km blinking, and localized redraw.
- Built and flashed firmware 1.3.2 to ESP32-S3 `14:C1:9F:27:03:44`. Serial
  output after flashing showed a named-road navigation update and the expected
  transition from `1.02 km` straight to `985 m` with the turn arrow blinking.
- Rebuilding/installing the local Android APK with the matching OsmAnd parser;
  this is not a public release. The new vector glyphs compiled and flashed,
  but no physical TFT photo/visual confirmation of the new roundabout/U-turn
  shapes was captured in this pass. The user's earlier visual confirmation
  was for the ordinary `Nguyen Hue · 250 m` sample, not these new shapes.
- No automated test suites or route simulation were run in this pass.

## Latest continuation — evening, 2026-10-02

This section supersedes the morning handoff below.

- Earlier approved simulation confirmed live OsmAnd API delivery after enabling
  **OsmAnd → Menu → Plugins → ESP32-NavRide**. The earlier subscription `-1`
  was resolved by that setting. Serial updates continued from 14:16:06 to
  14:17:00 while the phone screen was off (not a long Doze/endurance test).
- That simulation exposed roundabouts incorrectly converted to ordinary right
  turns, and transient pairing of the new maneuver with the previous road.
- Fixed: official `getAppInfo().turnInfo` next-turn fields now supply road,
  maneuver and distance together. Empty road names stay empty; packets no
  longer silently reuse cached road names. Snapshot reading catches API errors
  and falls back to typed directions. Notifications remain a fallback when no
  fresh API update is available. Connection/reconnection fetches the current
  snapshot instead of waiting for movement.
- Added `roundabout` / `roundabout_left` packet handling and circulation icons
  to firmware, retaining <2 km turn visibility, <1 km blinking and partial
  redraw. At that point the icons did not show an exit number; see the newer
  2026-10-03 iteration above.
- App resumes/reconnects the native bridge and explains restoring notification
  access when Android has stopped its listener. Help includes enabling NavRide
  in OsmAnd Plugins; TTS is optional for API street names.
- The first evening release still showed blank streets on a named road. R8
  mapping had renamed the cross-app Bundle Parcelable `ALatLon` to `v2.a`.
  A narrow keep rule now preserves its wire name and CREATOR while retaining
  optimization elsewhere. Rebuilt/installed release immediately delivered
  `DT.43 Tinh lo 43 92 m`. `bash App/tool/check_osmand_release.sh` verifies
  the release mapping; ordinary debug JUnit tests cannot cover this R8 issue.
- Verified again: Flutter analyzer clean, **36 Flutter tests**, **16 Kotlin
  tests**, release APK build and web build successful. Firmware compiled and
  uploaded with flash hash verification to ESP32-S3 `14:C1:9F:27:03:44`.
- Local Android build retains `261001.4` / `26100104`, package ID and data;
  public update artifacts were not replaced.
- Latest APK SHA-256:
  `7011a8cb55ace9983882a4e7e898c922a8c9dfd28f1a72fc93893b1c75ea662a`.
- Flashed firmware SHA-256:
  `7acc6bc399247925fec369f0c54b143813674a4be58d7ef8979747da02c833ae`.
- Restored this app's stopped notification listener through normal Android
  settings. Native BLE and OsmAnd subscriptions connected successfully; the
  final APK replacement then reconnected without another permission toggle.
- All four manual sample draw paths were observed in serial. The user directly
  confirmed that the `Nguyen Hue · 250 m` sample was clear and correct on TFT.
- With renewed stationary approval, simulated the phone's latest saved route.
  Final-release evidence at 20:55:44: `left DT.43 Tinh lo 43 32 m`; at 20:55:50:
  `left DT.743C Duong tinh 743C 3.02 km arrow=straight blink=no`. The next
  street changes together with the next maneuver/distance, without retaining
  the old road. Native matching ACKs continued while OsmAnd was foreground.
- Final-release simulation thresholds: 20:57:28 `2.03 km arrow=straight
  blink=no`; 20:57:31 `1.99 km arrow=left blink=no`; 20:59:07 `1.00 km
  arrow=left blink=no`; 20:59:11 `951 m arrow=left blink=yes`. Each packet
  retained the correct next road `DT.743C Duong tinh 743C`.
- Screen-off test: Android reported `mWakefulness=Dozing` at 20:58:05.
  Serial updates and matching phone ACKs continued for over one minute until
  waking at approximately 20:59:23. This is a short screen-off test, not proof
  of extended deep Doze or a complete ride.
- Turned **Simulate navigation OFF** after testing and asserted the actual
  Android switch was unchecked. Evidence: `App/build/ux/android-osmand-simulation-off.png`.
  The route destination was retained; phone remains on the native BLE bridge.
- Roundabout icons have parser/build validation but were not encountered on
  this particular simulated segment. Exit numbers are not rendered. Long Doze
  and real-road endurance remain unverified. Computer stays on; no shutdown.
- Local web preview/update server ports 8080/3000 were not listening during
  this continuation. No public APK publication or server restart was performed.

## Implemented

- Three stable app destinations: Navigation, Content, Settings. Neutral light
  appearance; no app color/background selector or seeded demo content.
- Content is saved locally and only sent explicitly. Delete supports Undo.
  Existing content, connection settings, legacy storage and Android ID remain.
- App labels, help, errors and TFT menus/status labels use English. User content,
  Wi-Fi credentials and street names are not translated. Vietnamese OsmAnd
  parsing is retained; TFT display text is transliterated to supported glyphs.
- Firmware 1.3.1 adds request-ID acknowledgements for notifications, tasks,
  clear, mode changes, Wi-Fi setup and ping; existing ID-less requests still work.
- Only acknowledged commands report successful delivery. HTTP 200 alone is not
  enough. Native BLE preserves pending control commands when directions arrive.
- Encoded BLE packets fit the ATT limit, including escaped quotes/backslashes.
  Display text may be shortened; credentials are byte-validated, never shortened.
- Native BLE subscribes to acknowledgements before use. An initial ping opens
  the connection before an OsmAnd route, and updates the UTC+7 clock.
- OsmAnd 5.4 notification parsing preserves title/body boundaries, extracts
  `Turn right and go <road>`, keeps road references such as `ĐT.43`, and removes
  the following leg distance/trip summary from the road name.
- When BLE becomes ready, the listener replays existing ongoing OsmAnd
  notifications. A route started before connecting no longer needs a new post.
- A matching navigation ACK no longer expires after 60 seconds on a stationary
  route. New directions and disconnection still require delivery confirmation.
  Native diagnostics log subscription results and ACK IDs, not route content.

## Verified

- `flutter analyze`: clean.
- `flutter test`: 34 passed, including missing ACK, input limits, storage,
  offline behavior, update integrity, responsive layout and enlarged text.
- Android app JUnit suite: 14 passed, including OsmAnd parsing and BLE packet
  encoding with the largest request ID and escaped/Vietnamese street names.
  Both new road-name regressions failed before the fix and passed afterward.
- Update backend test: passed; existing published manifest remains unchanged.
- Release APK and web builds: successful. Existing Android signing certificate
  and application ID `com.thanhhao.esp32_monitor` retained.
- Chromium: Navigation/Content/Settings at 375, 768, 1024 and 1440 px; screenshots
  in `App/build/ux/`. Created and sent a notification from the actual web UI.
- Flashed the attached ESP32-S3 (MAC 14:C1:9F:27:03:44). Health reports firmware
  1.3.1, SuBo Wi-Fi, IP 192.168.1.55 and UTC+7 local time.
- Hardware smoke test: HTTP accepted valid commands and rejected invalid ones;
  BLE returned matching ACK IDs for ping, notification, task, all navigation
  maneuvers, clear and mode switch. Invalid API version was rejected.
- Serial draw evidence: 2000 m → straight / 2.00 km; 1999 m → turn / 1.99 km;
  1000 m → steady turn / 1.00 km; 999 m → blinking turn / 999 m.
- Web delivery serial evidence: `DISPLAY: popup title=Web delivery test
  body=Nguyen Hue > 250 m`. Smoke test restored Wi-Fi after BLE checks.

## Earlier real phone verification — morning, 2026-10-02

- ADB phone: realme RMX5060, Android 16; installed OsmAnd `net.osmand` 5.4.6.
  Installed the local release APK with `adb install -r`; existing application
  ID, data and selected ESP32 were retained. Notification access is enabled.
- Phone native BLE connected to ESP32-NavRide, negotiated MTU 185 and subscribed
  to the acknowledgement characteristic. Wi-Fi is not the delivery transport.
- Actual app Left sample produced the serial draw event:
  `DISPLAY: navigation left Nguyen Hue 250 m arrow=left blink=yes`.
- The existing OsmAnd route notification contained a 60 m right turn, road
  `ĐT.43 Tỉnh lộ 43`, a 1.6 km following leg and a 6.6 km total. After the fix,
  the firmware logged:
  `DISPLAY: navigation right DT.43 Tinh lo 43 60 m arrow=right blink=yes`.
  NavRide showed `ESP32 confirmed the latest directions from OsmAnd.`
- Final APK background replay: OsmAnd was the focused activity while NavRide
  received `Navigation acknowledged: requestId=3` at 09:15:59 local time.
  This verifies a short background delivery, not an extended riding/Doze test.
- Returning to NavRide at approximately 09:17:30 still showed the confirmed
  directions state and Bluetooth connected; the former 60-second false waiting
  state did not recur. Phone UI evidence: `App/build/ux/android-navride-confirmed.png`.
- OsmAnd AIDL bound successfully but returned -1 for both direction and voice
  subscription; the successful real-phone data path is notification fallback.
  API permission/subscription acceptance is NOT verified.
- Final manual-install APK SHA-256:
  `2d616ccbcb8824455ad11ff6d965fcba0d938ba4c7f138cd36ff0624958c7ad9`.

## Earlier handoff and limits (see latest continuation above)

- Preview: http://192.168.1.149:8080 (use localhost:8080 on this computer for
  Web Bluetooth). Update backend: http://192.168.1.149:3000.
- Manual-install test APK: `App/build/app/outputs/flutter-apk/app-release.apk`.
  This local build keeps version 261001.4 / code 26100104. It has NOT replaced
  the published APK; in-app updates require a separately authorized new version.
- The ESP32 is now left connected to the phone over Bluetooth, so its prior
  Wi-Fi HTTP address is intentionally unavailable. The user's OsmAnd route was
  retained; no replacement route or simulated GPS location was injected.
- Continuous route progression, extended locked-screen/background behavior and
  manual button operation still require on-device testing. Firmware draw logs
  are not a visual inspection of TFT pixels; physical display confirmation is
  still pending from the user.
- Before riding, test a simulated OsmAnd route while parked: connect Bluetooth,
  enable notification access, open OsmAnd and start navigation. Street names
  depend on OsmAnd supplying them in notifications or TTS prompts.
- Computer remains on; no shutdown is scheduled. Preview/backend are transient
  user services for this session, not new boot-time services.

Reusable checks: `App/tool/web_smoke.cjs` (Playwright) and
`Firmware/tools/smoke_test.py` (bleak + pyserial; changes device mode/test content).
