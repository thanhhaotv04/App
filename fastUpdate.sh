#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
APP_VERSION_FILE="$ROOT_DIR/lib/src/app_version.dart"
MANIFEST_FILE="$ROOT_DIR/backend/releases/latest.json"
BUILD_APK="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
RELEASE_APK="$ROOT_DIR/backend/releases/app-release.apk"
SERVER_LOG="$ROOT_DIR/backend/server.log"

REQUESTED_PORT="${PORT:-3000}"
TARGET_VERSION=""
UPDATE_NOTES=""
BACKUP_DIR=""
SERVER_PID=""
SERVER_PORT=""
SERVER_STARTED=0
COMMIT_DONE=0
RELEASE_WAS_PRESENT=0

usage() {
  cat <<'EOF'
Usage:
  ./fastUpdate.sh [options]

Options:
  --version 260918.1+26091801
                         Use an explicit YYMMDD.N release and build number.
  --port 3000         Start or reuse the backend from this port.
  --notes "..."       Notes shown in the in-app update dialog.
  -h, --help          Show this help.

The default flow selects the next YYMMDD.N release in Asia/Ho_Chi_Minh, runs checks,
builds an Android ARM64 APK, publishes it to backend/releases, starts the LAN
backend, and verifies /api/update/latest.
EOF
}

die() {
  echo "fastUpdate.sh: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || die "--version needs a value such as 260918.1+26091801"
      TARGET_VERSION="$2"
      shift 2
      ;;
    --port)
      [[ $# -ge 2 ]] || die "--port needs a number"
      REQUESTED_PORT="$2"
      shift 2
      ;;
    --notes)
      [[ $# -ge 2 ]] || die "--notes needs a value"
      UPDATE_NOTES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

[[ "$REQUESTED_PORT" =~ ^[0-9]+$ ]] || die "Port must be numeric: $REQUESTED_PORT"
(( REQUESTED_PORT >= 1 && REQUESTED_PORT <= 65535 )) || die "Port must be between 1 and 65535"

for command in flutter node npm curl sha256sum; do
  require_command "$command"
done

[[ -f "$PUBSPEC_FILE" ]] || die "Cannot find pubspec.yaml"
[[ -f "$APP_VERSION_FILE" ]] || die "Cannot find lib/src/app_version.dart"
[[ -f "$MANIFEST_FILE" ]] || die "Cannot find backend/releases/latest.json"

PUBSPEC_VERSION="$(sed -nE 's/^version: ([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$/\1/p' "$PUBSPEC_FILE")"
APP_VERSION_NAME="$(sed -nE "s/.*versionName = '([^']+)';/\1/p" "$APP_VERSION_FILE")"
APP_VERSION_CODE="$(sed -nE 's/.*versionCode = ([0-9]+);/\1/p' "$APP_VERSION_FILE")"

[[ -n "$PUBSPEC_VERSION" ]] || die "Could not read version from pubspec.yaml"
[[ -n "$APP_VERSION_NAME" && -n "$APP_VERSION_CODE" ]] || die "Could not read AppVersion"

PUBSPEC_NAME="${PUBSPEC_VERSION%+*}"
PUBSPEC_CODE="${PUBSPEC_VERSION##*+}"
PUBSPEC_LABEL="$PUBSPEC_NAME"
if [[ "$PUBSPEC_NAME" =~ ^([0-9]{6}\.[0-9]+)\.0$ ]]; then
  PUBSPEC_LABEL="${BASH_REMATCH[1]}"
fi
[[ "$PUBSPEC_LABEL" == "$APP_VERSION_NAME" && "$PUBSPEC_CODE" == "$APP_VERSION_CODE" ]] || \
  die "Version mismatch: pubspec=$PUBSPEC_VERSION, AppVersion=$APP_VERSION_NAME+$APP_VERSION_CODE"

MANIFEST_CODE="$(node -e '
const fs = require("fs");
const file = process.argv[1];
try {
  const json = JSON.parse(fs.readFileSync(file, "utf8"));
  process.stdout.write(String(Number(json.versionCode) || 0));
} catch {
  process.stdout.write("0");
}
' "$MANIFEST_FILE")"

if [[ -z "$TARGET_VERSION" ]]; then
  RELEASE_DATE="$(TZ=Asia/Ho_Chi_Minh date +%y%m%d)"
  MANIFEST_NAME="$(node -e '
const fs = require("fs");
const json = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
process.stdout.write(String(json.versionName || ""));
' "$MANIFEST_FILE")"
  DAILY_NUMBER=1
  if [[ "$MANIFEST_NAME" =~ ^${RELEASE_DATE}\.([0-9]+)$ ]]; then
    DAILY_NUMBER=$((BASH_REMATCH[1] + 1))
  fi
  TARGET_CODE="${RELEASE_DATE}$(printf '%02d' "$DAILY_NUMBER")"
  TARGET_VERSION="${RELEASE_DATE}.${DAILY_NUMBER}+${TARGET_CODE}"
fi

if [[ ! "$TARGET_VERSION" =~ ^([0-9]{6})\.([0-9]+)\+([0-9]+)$ ]]; then
  die "Invalid version: $TARGET_VERSION (expected YYMMDD.N+buildNumber)"
fi
TARGET_NAME="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
TARGET_CODE="${BASH_REMATCH[3]}"
TARGET_PUBSPEC_VERSION="${TARGET_NAME}.0+${TARGET_CODE}"

(( TARGET_CODE > PUBSPEC_CODE )) || die "Target versionCode must be greater than $PUBSPEC_CODE"
(( TARGET_CODE > MANIFEST_CODE )) || die "Target versionCode must be greater than backend manifest $MANIFEST_CODE"

if [[ -z "$UPDATE_NOTES" ]]; then
  UPDATE_NOTES="Improvements and bug fixes."
fi

BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vietnam-map-fast-update.XXXXXX")"
cp "$PUBSPEC_FILE" "$BACKUP_DIR/pubspec.yaml"
cp "$APP_VERSION_FILE" "$BACKUP_DIR/app_version.dart"
cp "$MANIFEST_FILE" "$BACKUP_DIR/latest.json"
if [[ -f "$RELEASE_APK" ]]; then
  cp "$RELEASE_APK" "$BACKUP_DIR/app-release.apk"
  RELEASE_WAS_PRESENT=1
fi

restore_on_failure() {
  local status=$?
  if (( status != 0 && COMMIT_DONE == 0 )); then
    cp "$BACKUP_DIR/pubspec.yaml" "$PUBSPEC_FILE"
    cp "$BACKUP_DIR/app_version.dart" "$APP_VERSION_FILE"
    cp "$BACKUP_DIR/latest.json" "$MANIFEST_FILE"
    if (( RELEASE_WAS_PRESENT == 1 )); then
      cp "$BACKUP_DIR/app-release.apk" "$RELEASE_APK"
    else
      rm -f "$RELEASE_APK"
    fi
    echo "Build/update failed; source version and published APK were restored." >&2
  fi
  if (( status != 0 && SERVER_STARTED == 1 )) && [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$BACKUP_DIR"
  exit "$status"
}
trap restore_on_failure EXIT

echo "Current version: $PUBSPEC_VERSION"
echo "New version:     $TARGET_NAME+$TARGET_CODE"

if [[ ! -d "$ROOT_DIR/node_modules" ]]; then
  echo "Installing backend dependencies..."
  npm install
fi

echo "Running backend syntax check..."
node --check backend/server.js

echo "Updating local version files..."
sed -i -E "s/^version: [^[:space:]]+/version: $TARGET_PUBSPEC_VERSION/" "$PUBSPEC_FILE"
sed -i -E "s/(versionName = ')[^']+('.*)/\1$TARGET_NAME\2/" "$APP_VERSION_FILE"
sed -i -E "s/(versionCode = )[0-9]+(;.*)/\1$TARGET_CODE\2/" "$APP_VERSION_FILE"

echo "Fetching Flutter dependencies..."
flutter pub get

echo "Running Flutter analyzer..."
flutter analyze

echo "Running Flutter tests..."
flutter test

echo "Building Android ARM64 release APK..."
flutter build apk --release --target-platform android-arm64 \
  --build-name="$TARGET_NAME" --build-number="$TARGET_CODE"
[[ -s "$BUILD_APK" ]] || die "Flutter build did not produce $BUILD_APK"

# The update manifest must describe the APK that Android will actually install.
SDK_DIR="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$SDK_DIR" && -f android/local.properties ]]; then
  SDK_DIR="$(sed -n 's/^sdk.dir=//p' android/local.properties | sed -n '1p')"
fi
AAPT_BIN="$(command -v aapt || true)"
if [[ -z "$AAPT_BIN" && -d "$SDK_DIR/build-tools" ]]; then
  AAPT_BIN="$(find "$SDK_DIR/build-tools" -mindepth 2 -maxdepth 2 -type f -name aapt | sort -V | tail -n 1)"
fi
[[ -n "$AAPT_BIN" ]] || die "Cannot find Android aapt to verify the APK version"
APK_PACKAGE_LINE="$("$AAPT_BIN" dump badging "$BUILD_APK" | sed -n '1p')"
APK_CODE="$(sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" <<< "$APK_PACKAGE_LINE")"
APK_NAME="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<< "$APK_PACKAGE_LINE")"
[[ "$APK_NAME" == "$TARGET_NAME" && "$APK_CODE" == "$TARGET_CODE" ]] || \
  die "Built APK is $APK_NAME+$APK_CODE, expected $TARGET_VERSION"
EXPECTED_PACKAGE="$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' android/app/build.gradle.kts | sed -n '1p')"
[[ -z "$EXPECTED_PACKAGE" || "$APK_PACKAGE_LINE" == *"name='$EXPECTED_PACKAGE'"* ]] || \
  die "Built APK has the wrong application ID: $APK_PACKAGE_LINE"

if [[ -f "$RELEASE_APK" ]]; then
  APKSIGNER_BIN="$(dirname "$AAPT_BIN")/apksigner"
  [[ -x "$APKSIGNER_BIN" ]] || die "Cannot find Android apksigner to verify update signing"
  old_signer="$("$APKSIGNER_BIN" verify --print-certs "$RELEASE_APK" 2>/dev/null | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | sed -n '1p')"
  new_signer="$("$APKSIGNER_BIN" verify --print-certs "$BUILD_APK" 2>/dev/null | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | sed -n '1p')"
  [[ -n "$old_signer" && "$old_signer" == "$new_signer" ]] || \
    die "Built APK signing certificate does not match the published APK"
fi

port_is_listening() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnH "sport = :$1" 2>/dev/null | grep -q .
    return
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN 2>/dev/null | grep -q .
    return
  fi
  return 1
}

backend_health() {
  local port="$1"
  curl -fsS --max-time 1 "http://127.0.0.1:$port/api/health" 2>/dev/null | grep -q 'vietnam-map-backend'
}

SERVER_PORT=""
for candidate in $(seq "$REQUESTED_PORT" $((REQUESTED_PORT + 20))); do
  if backend_health "$candidate"; then
    SERVER_PORT="$candidate"
    echo "Reusing backend already running on port $SERVER_PORT."
    break
  fi
  if ! port_is_listening "$candidate"; then
    SERVER_PORT="$candidate"
    echo "Starting backend on port $SERVER_PORT..."
    if command -v setsid >/dev/null 2>&1; then
      setsid env PORT="$SERVER_PORT" npm run backend >"$SERVER_LOG" 2>&1 < /dev/null &
    else
      nohup env PORT="$SERVER_PORT" npm run backend >"$SERVER_LOG" 2>&1 < /dev/null &
    fi
    SERVER_PID=$!
    SERVER_STARTED=1
    break
  fi
done

[[ -n "$SERVER_PORT" ]] || die "No available backend port from $REQUESTED_PORT to $((REQUESTED_PORT + 20))"

for attempt in $(seq 1 30); do
  if backend_health "$SERVER_PORT"; then
    break
  fi
  if (( attempt == 30 )); then
    tail -n 40 "$SERVER_LOG" >&2 || true
    die "Backend health check timed out"
  fi
  sleep 0.5
done

echo "Publishing APK and update manifest..."
cp "$BUILD_APK" "$RELEASE_APK"
VERSION_NAME="$TARGET_NAME" \
VERSION_CODE="$TARGET_CODE" \
UPDATE_NOTES="$UPDATE_NOTES" \
MANIFEST_FILE="$MANIFEST_FILE" \
node <<'NODE'
const fs = require('fs');
const file = process.env.MANIFEST_FILE;
const old = JSON.parse(fs.readFileSync(file, 'utf8'));
const next = {
  versionName: process.env.VERSION_NAME,
  versionCode: Number(process.env.VERSION_CODE),
  apkFile: 'app-release.apk',
  notes: process.env.UPDATE_NOTES || old.notes || '',
};
fs.writeFileSync(file, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
NODE

UPDATE_JSON="$(curl -fsS --max-time 5 "http://127.0.0.1:$SERVER_PORT/api/update/latest")" || die "Update endpoint is not reachable"
VERSION_NAME="$TARGET_NAME" VERSION_CODE="$TARGET_CODE" UPDATE_JSON="$UPDATE_JSON" node <<'NODE'
const payload = JSON.parse(process.env.UPDATE_JSON);
if (payload.versionName !== process.env.VERSION_NAME || Number(payload.versionCode) !== Number(process.env.VERSION_CODE)) {
  throw new Error(`Manifest mismatch: ${JSON.stringify(payload)}`);
}
if (!payload.apkUrl) throw new Error('Update endpoint did not return apkUrl');
NODE

curl -fsS --max-time 30 "http://127.0.0.1:$SERVER_PORT/releases/app-release.apk" -o "$BACKUP_DIR/served.apk" || \
  die "Published APK cannot be downloaded"
cmp -s "$RELEASE_APK" "$BACKUP_DIR/served.apk" || \
  die "Backend is serving an APK different from the published file"

COMMIT_DONE=1
SHA256="$(sha256sum "$RELEASE_APK" | awk '{print $1}')"
LAN_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -z "$LAN_IP" ]]; then
  LAN_IP="127.0.0.1"
fi

echo
echo "Update is ready."
echo "Version:       $TARGET_VERSION"
echo "APK SHA-256:   $SHA256"
echo "Backend health: http://127.0.0.1:$SERVER_PORT/api/health"
echo "Update check:  http://127.0.0.1:$SERVER_PORT/api/update/latest"
echo "Phone backend: http://$LAN_IP:$SERVER_PORT"
echo "APK download:  http://$LAN_IP:$SERVER_PORT/releases/app-release.apk"
echo
echo "On the phone: Account > Backend URL > http://$LAN_IP:$SERVER_PORT > Check for update."
echo "Backend log:  $SERVER_LOG"
if (( SERVER_STARTED == 1 )); then
  echo "Backend PID:   $SERVER_PID"
fi

rm -rf "$BACKUP_DIR"
BACKUP_DIR=""
trap - EXIT
