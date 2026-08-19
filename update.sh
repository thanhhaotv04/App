#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_SLUG="task-reminder"
PUBSPEC="$ROOT_DIR/pubspec.yaml"
MANIFEST="$ROOT_DIR/backend/releases/latest.json"
APK_FILE="app-release-$APP_SLUG.apk"
BACKEND_APK="$ROOT_DIR/backend/releases/$APK_FILE"
BUILD_APK="$ROOT_DIR/build/app/outputs/flutter-apk/$APK_FILE"
BACKEND_PORT="${BACKEND_PORT:-3002}"
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
HOST_IP="${HOST_IP:-127.0.0.1}"

usage() {
  cat <<USAGE
Usage:
  ./update.sh
  VERSION_NAME=1.0.5 VERSION_CODE=6 RELEASE_NOTES="Bug fixes" ./update.sh
  ./update.sh --serve

Options:
  --serve      Start the backend after building so the app can check updates.
  --no-web     Skip flutter build web.
  --help       Show this help.

Environment:
  VERSION_NAME    Override the next version name. Default: bump patch.
  VERSION_CODE    Override the next Android version code. Default: +1.
  RELEASE_NOTES   Notes shown in the app update dialog.
  BACKEND_PORT    Backend port when using --serve. Default: 3002.
USAGE
}

SERVE_BACKEND=0
BUILD_WEB=1
for arg in "$@"; do
  case "$arg" in
    --serve)
      SERVE_BACKEND=1
      ;;
    --no-web)
      BUILD_WEB=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage
      exit 2
      ;;
  esac
done

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing command: $1" >&2
    exit 1
  fi
}

require_cmd flutter
require_cmd dart
require_cmd node
require_cmd npm

cd "$ROOT_DIR"

if [[ ! -f "$PUBSPEC" ]]; then
  echo "Cannot find $PUBSPEC" >&2
  exit 1
fi

CURRENT_VERSION="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+).*/\1+\2/p' "$PUBSPEC" | head -1)"
if [[ -z "$CURRENT_VERSION" ]]; then
  echo "Cannot read current version from pubspec.yaml" >&2
  exit 1
fi

CURRENT_NAME="${CURRENT_VERSION%%+*}"
CURRENT_CODE="${CURRENT_VERSION##*+}"
IFS='.' read -r MAJOR MINOR PATCH <<<"$CURRENT_NAME"

NEXT_NAME="${VERSION_NAME:-$MAJOR.$MINOR.$((PATCH + 1))}"
NEXT_CODE="${VERSION_CODE:-$((CURRENT_CODE + 1))}"
RELEASE_NOTES="${RELEASE_NOTES:-Feature updates and bug fixes.}"

if ! [[ "$NEXT_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION_NAME must look like 1.0.4" >&2
  exit 1
fi
if ! [[ "$NEXT_CODE" =~ ^[0-9]+$ ]]; then
  echo "VERSION_CODE must be a positive number" >&2
  exit 1
fi
if (( NEXT_CODE <= CURRENT_CODE )); then
  echo "VERSION_CODE must be greater than current code $CURRENT_CODE" >&2
  exit 1
fi

echo "Updating $CURRENT_VERSION -> $NEXT_NAME+$NEXT_CODE"

export UPDATE_PUBSPEC="$PUBSPEC"
export UPDATE_MANIFEST="$MANIFEST"
export UPDATE_VERSION_NAME="$NEXT_NAME"
export UPDATE_VERSION_CODE="$NEXT_CODE"
export UPDATE_APK_FILE="$APK_FILE"
export UPDATE_RELEASE_NOTES="$RELEASE_NOTES"

node --input-type=module <<'NODE'
import fs from "fs";
import path from "path";

const pubspecPath = process.env.UPDATE_PUBSPEC;
const manifestPath = process.env.UPDATE_MANIFEST;
const nextName = process.env.UPDATE_VERSION_NAME;
const nextCode = Number(process.env.UPDATE_VERSION_CODE);
const apkFile = process.env.UPDATE_APK_FILE;
const notes = process.env.UPDATE_RELEASE_NOTES;

let pubspec = fs.readFileSync(pubspecPath, "utf8");
if (!/^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+/m.test(pubspec)) {
  throw new Error("pubspec.yaml does not contain a valid version line");
}
pubspec = pubspec.replace(
  /^version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+/m,
  `version: ${nextName}+${nextCode}`,
);
fs.writeFileSync(pubspecPath, pubspec);

fs.mkdirSync(path.dirname(manifestPath), { recursive: true });
fs.writeFileSync(
  manifestPath,
  JSON.stringify(
    {
      versionName: nextName,
      versionCode: nextCode,
      apkFile,
      notes,
    },
    null,
    2,
  ) + "\n",
);
NODE

flutter pub get
dart format --set-exit-if-changed lib test
flutter analyze
flutter test

(
  cd "$ROOT_DIR/backend"
  node --check server.js
  npm test
)

if (( BUILD_WEB == 1 )); then
  flutter build web
fi

"$ROOT_DIR/tools/build_release_apk.sh"

if [[ ! -s "$BUILD_APK" ]]; then
  echo "Missing built APK: $BUILD_APK" >&2
  exit 1
fi
if [[ ! -s "$BACKEND_APK" ]]; then
  echo "Missing backend APK: $BACKEND_APK" >&2
  exit 1
fi

node --input-type=module <<'NODE'
import fs from "fs";
const manifest = JSON.parse(fs.readFileSync(process.env.UPDATE_MANIFEST, "utf8"));
if (manifest.versionName !== process.env.UPDATE_VERSION_NAME) {
  throw new Error("latest.json versionName mismatch");
}
if (Number(manifest.versionCode) !== Number(process.env.UPDATE_VERSION_CODE)) {
  throw new Error("latest.json versionCode mismatch");
}
if (manifest.apkFile !== process.env.UPDATE_APK_FILE) {
  throw new Error("latest.json apkFile mismatch");
}
NODE

echo
echo "Release is ready."
echo "Version: $NEXT_NAME+$NEXT_CODE"
echo "APK: $BUILD_APK"
echo "Backend APK: $BACKEND_APK"
echo "Update endpoint: http://$HOST_IP:$BACKEND_PORT/api/update/latest"

if (( SERVE_BACKEND == 1 )); then
  echo
  if command -v ss >/dev/null 2>&1 &&
    ss -ltn | awk '{print $4}' | grep -Eq "(^|:)$BACKEND_PORT$"; then
    echo "Backend already appears to be running on port $BACKEND_PORT."
    echo "Use: http://$HOST_IP:$BACKEND_PORT/api/update/latest"
    exit 0
  fi
  echo "Starting backend on 0.0.0.0:$BACKEND_PORT"
  cd "$ROOT_DIR/backend"
  PORT="$BACKEND_PORT" npm start
fi
