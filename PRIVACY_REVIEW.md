# Privacy review — 2026-10-08–09

## Changes in the current source

- FlutterBluePlus payload logging is disabled before scanning or connecting.
  Firmware serial output no longer includes notification bodies/titles, road
  names, speeds, SSIDs or local IPs.
- Notification processing accepts exactly `net.osmand`, `net.osmand.plus` and
  `net.osmand.dev`; similarly named third-party packages are rejected before
  reading their notification text.
- Android cloud backup and device transfer exclude the app's local files,
  preferences and databases. Saved content and pairing PINs stay in the app
  sandbox. This does not add application-level encryption at rest.
- Pairing PINs and Wi-Fi passwords are masked, do not use keyboard suggestions,
  and are hidden again when the app enters the background. Wi-Fi passwords are
  not persisted by the Flutter app.
- Device HTTP requests reject redirects. Public addresses require HTTPS;
  local ESP32 HTTP remains available for compatibility with the firmware.
- `Settings → Privacy and data` explains data use and offers permission settings
  and confirmed deletion of saved content, PINs, connection settings, legacy
  data, recovery copies and Android update downloads. Deletion stops native
  GPS/navigation sharing. Android grants, system pairings and ESP32 data are
  managed separately and are explicitly described in the confirmation.
- Personal QR bitmaps and their optional payment caption are kept in the
  ignored `Firmware/include/qr_assets_private.h`. The public wrapper has empty
  defaults; builds without the private header show `QR not set`. Local QR
  functionality is retained. Documentation omits the personal payloads.
- Content cards have a direct send button and an Edit action; edits preserve
  identity, creation time, priority, task completion and due dates.

## Historical exposure and prepared cleanup

Commit `bbb385153172b2dba1b1627819863ddbe09f41ad` contains personal payment
information, a profile redirect and their QR bitmaps. Removing them from the
latest source does not remove them from that published commit.

A history rewrite was prepared and tested in an isolated clone. It replaces
the original QR bitmaps with neutral example QR codes and redacts the payment
number and profile redirect in all text blobs. The preview changes that commit
to `18aa6ab645fc2b37c98e5ded307520921a13761d`; the initial commit remains unchanged.
The scan of every blob reachable from the preview branch confirms that the
identified originals are absent. The live repository and GitHub history were
not rewritten as part of this preview. Publishing the cleanup requires an
explicitly approved `--force-with-lease` update of `ESP32-NavRide`.

Rewriting a branch cannot erase previously downloaded clones, forks or cached
GitHub commit views. GitHub Support may be needed to remove retained views.
No statement here guarantees that already published personal data can be
recalled from everyone who had access to it.

## Limits and references

- Local HTTP is not encrypted. Use trusted Wi-Fi or authenticated Bluetooth
  when sending private content or Wi-Fi credentials.
- Fleet tracking is opt-in: after the driver signs in and starts a trip, the
  foreground location service sends current GPS coordinates and speed to the
  assigned vehicle's Firebase Firestore document. It stops on End trip and
  clears coordinates in the final status. Route points are saved separately
  after five minutes online or ten minutes offline and 100 m of movement;
  Firestore's Android disk cache queues offline writes for later upload. Trip
  start/end records are stored separately. Uploaded records remain until an authorized
  administrator removes them; local data deletion does not remove them.
  Mock locations are rejected. Personal
  notifications, QR assets and OsmAnd directions are not uploaded. There is no
  analytics collection. OsmAnd and the user-selected update server have separate data
  handling. This review does not audit those external applications/services.
- Existing published APKs are unchanged; these fixes require a newly built
  app and firmware. The current Android package is `com.thanhhao.esp32_navride`;
  existing `com.thanhhao.esp32_monitor` installations are separate apps and
  their data/permissions must be managed separately. The backend intentionally
  rejects its old published manifest until a matching new release is published.
  Release signing still uses the existing debug signing
  configuration; a production signing migration needs a separate release plan
  to preserve installation compatibility.
- Android backup rules follow [Auto Backup documentation](https://developer.android.com/identity/data/autobackup).
  Logging changes follow [Android log disclosure guidance](https://developer.android.com/privacy-and-security/risks/log-info-disclosure).
- Validation evidence is recorded in [VALIDATION.md](VALIDATION.md).
