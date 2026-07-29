# Safe backup and sync runbook

## First rule: do not uninstall the recovered app

Android app-private check-ins and photos can be erased by uninstalling. Keep the
installed `1.0.14+21` APK until a JSON/backend backup is verified. Do not install
a rebuilt APK over it unless its package and signing certificate both match the
values in `README.md`.

## Preferred recovery from the installed phone

1. Start the repository backend on a PC.
2. In the phone app, set Backend URL to the PC's LAN address, for example
   `http://192.168.1.10:3000`.
3. Use Sync now while both devices are on the same network.
4. Verify `GET /api/checkins` returns the expected count and recent IDs.
5. Back up both of these backend trees:
   - `backend/server-data/`
   - `backend/user/Picture/thanhhao/`

The JSON alone is not a complete backup when check-ins reference photo paths.

Example verification:

```bash
curl http://192.168.1.10:3000/api/health
curl http://192.168.1.10:3000/api/checkins > checkins-backup.json
```

## If the phone cannot reach the backend

- Confirm the PC firewall allows the selected Node/Express port.
- Use the PC's LAN IP, not `127.0.0.1`; on the phone, localhost means the phone.
- Confirm the backend printed the actual port. It tries ports 3000 through 3019
  when a port is occupied.
- Open `/api/health` in the phone browser before retrying Sync.

## Direct Android private-data extraction

The important device paths and keys are documented in `README.md`. Normal
release Android apps do not allow `adb pull` from `/data/user/0/...`. Direct
extraction generally requires an already-authorized root/debug route. Do not
unlock the bootloader merely to recover this data: many devices erase user data
during bootloader unlock.

## Restore order

1. Restore backend photo files without changing their relative paths.
2. Restore `backend/server-data/checkins.json`.
3. Start backend and verify `/api/checkins`.
4. Configure the app to the restored backend.
5. Run two-way sync and compare item IDs/counts.
6. Keep the original backup until photo previews and several old/new check-ins
   have been checked on the phone.

The merge key is `id`, so preserve IDs. Changing an ID creates a duplicate
instead of updating the original record.
