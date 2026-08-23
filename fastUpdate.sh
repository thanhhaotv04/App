#!/usr/bin/env bash

# Build and publish a Money Manager LAN update without upgrading dependencies.
set -Eeuo pipefail
IFS=$'\n\t'

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PUBSPEC_FILE="$ROOT_DIR/pubspec.yaml"
readonly SERVICE_FILE="$ROOT_DIR/lib/src/services.dart"
readonly BACKEND_DIR="$ROOT_DIR/backend"
readonly RELEASES_DIR="$BACKEND_DIR/releases"
readonly MANIFEST_FILE="$RELEASES_DIR/latest.json"
readonly DATA_DIR="$BACKEND_DIR/server-data"
readonly LOCK_FILE="$DATA_DIR/fast-update.lock"
readonly PID_FILE="$DATA_DIR/fast-update-backend.pid"
readonly LOG_FILE="$DATA_DIR/fast-update-backend.log"

PORT=3002
NOTES=""
DRY_RUN=0
SOURCE_UPDATE_STARTED=0
MANIFEST_UPDATED=0
APK_TARGET_CREATED=0
RELEASE_SUCCEEDED=0
OLD_PUBSPEC_VERSION=""
OLD_VERSION_NAME=""
OLD_VERSION_CODE=""
NEW_PUBSPEC_VERSION=""
NEW_VERSION_NAME=""
NEW_VERSION_CODE=""
PUBSPEC_BACKUP=""
SERVICE_BACKUP=""
MANIFEST_BACKUP=""
TMP_APK=""

cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: ./fastUpdate.sh [options]

Options:
  --notes <text>  Release notes shown in the app.
  --port <port>   Backend port (default: 3002).
  --dry-run       Show the next version without changing files or starting a server.
  -h, --help      Show this help.

Optional environment variable:
  LAN_IP=<IPv4>   LAN address printed for the phone to use.
EOF
}

die() {
  echo "fastUpdate: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

while (($#)); do
  case "$1" in
    --notes)
      (($# >= 2)) || die "--notes requires text"
      NOTES="$2"
      shift 2
      ;;
    --port)
      (($# >= 2)) || die "--port requires a value"
      PORT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
  esac
done

[[ "$PORT" =~ ^[1-9][0-9]{0,4}$ ]] || die "Port must be an integer from 1 to 65535"
((10#$PORT <= 65535)) || die "Port must be an integer from 1 to 65535"

for command in curl dart date flock git mktemp node npm ss flutter; do
  require_command "$command"
done

for file in "$PUBSPEC_FILE" "$SERVICE_FILE" "$MANIFEST_FILE" "$BACKEND_DIR/server.js"; do
  [[ -f "$file" ]] || die "Required file not found: $file"
done

read_version_state() {
  node --input-type=module - "$PUBSPEC_FILE" "$SERVICE_FILE" "$MANIFEST_FILE" <<'NODE'
import fs from 'node:fs';

const [pubspecPath, servicePath, manifestPath] = process.argv.slice(2);
const pubspec = fs.readFileSync(pubspecPath, 'utf8');
const service = fs.readFileSync(servicePath, 'utf8');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));

function exactlyOneMatch(source, pattern, label) {
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) throw new Error(`Expected one ${label}, found ${matches.length}`);
  return matches[0];
}

const pubspecMatch = exactlyOneMatch(
  pubspec,
  /^version:\s*([^\s#]+)(?:\s+#.*)?$/gm,
  'pubspec version',
);
const pubspecVersion = pubspecMatch[1];
const semver = /^(\d+)\.(\d+)\.(\d+)\+(\d+)$/.exec(pubspecVersion);
if (!semver) throw new Error(`pubspec version is not x.y.z+build: ${pubspecVersion}`);

function dartStringValue(constantName) {
  const match = exactlyOneMatch(
    service,
    new RegExp(`static const ${constantName} = '([^']*)';`, 'g'),
    constantName,
  );
  return match[1];
}

function dartIntegerValue(constantName) {
  const match = exactlyOneMatch(
    service,
    new RegExp(`static const ${constantName} = (\\d+);`, 'g'),
    constantName,
  );
  return match[1];
}

const serviceName = dartStringValue('currentVersionName');
const serviceCode = dartIntegerValue('currentVersionCode');
const manifestName = String(manifest.versionName ?? '');
const manifestCode = String(manifest.versionCode ?? '');
for (const [label, value] of [
  ['pubspec build number', semver[4]],
  ['service version code', serviceCode],
  ['manifest version code', manifestCode],
]) {
  if (!/^\d+$/.test(value)) throw new Error(`${label} is not an integer: ${value}`);
}

console.log([
  pubspecVersion,
  semver[4],
  serviceName,
  serviceCode,
  manifestName,
  manifestCode,
].join('\t'));
NODE
}

apply_versions() {
  local from_pubspec="$1"
  local from_name="$2"
  local from_code="$3"
  local to_pubspec="$4"
  local to_name="$5"
  local to_code="$6"
  node --input-type=module - "$PUBSPEC_FILE" "$SERVICE_FILE" "$from_pubspec" "$from_name" "$from_code" "$to_pubspec" "$to_name" "$to_code" <<'NODE'
import fs from 'node:fs';

const [pubspecPath, servicePath, fromPubspec, fromName, fromCode, toPubspec, toName, toCode] = process.argv.slice(2);

function replaceOne(source, from, to, label) {
  const index = source.indexOf(from);
  if (index < 0 || source.indexOf(from, index + from.length) >= 0) {
    throw new Error(`Expected exactly one ${label}`);
  }
  return `${source.slice(0, index)}${to}${source.slice(index + from.length)}`;
}

const nextPubspec = replaceOne(
  fs.readFileSync(pubspecPath, 'utf8'),
  `version: ${fromPubspec}`,
  `version: ${toPubspec}`,
  'pubspec version line',
);
let nextService = fs.readFileSync(servicePath, 'utf8');
nextService = replaceOne(
  nextService,
  `static const currentVersionName = '${fromName}';`,
  `static const currentVersionName = '${toName}';`,
  'version name line',
);
nextService = replaceOne(
  nextService,
  `static const currentVersionCode = ${fromCode};`,
  `static const currentVersionCode = ${toCode};`,
  'version code line',
);

for (const [path, contents] of [[pubspecPath, nextPubspec], [servicePath, nextService]]) {
  const tempPath = `${path}.fast-update-${process.pid}.tmp`;
  fs.writeFileSync(tempPath, contents);
  fs.renameSync(tempPath, path);
}
NODE
}

restore_backup() {
  local backup_path="$1"
  local target_path="$2"
  local label="$3"
  [[ -n "$backup_path" && -e "$backup_path" ]] || return 0
  echo "fastUpdate: restoring ${label}" >&2
  mv -f -- "$backup_path" "$target_path"
}

discard_backup() {
  local backup_path="$1"
  [[ -n "$backup_path" && -e "$backup_path" ]] || return 0
  rm -f -- "$backup_path"
}

restore_release_on_failure() {
  local exit_code=$?
  local rollback_failed=0
  trap - EXIT
  set +e

  if ((RELEASE_SUCCEEDED == 0)); then
    echo "fastUpdate: release failed; rolling back changed release files" >&2

    if [[ -n "$TMP_APK" && -e "$TMP_APK" ]]; then
      rm -f -- "$TMP_APK" || rollback_failed=1
    fi
    if ((APK_TARGET_CREATED)) && [[ -n "${APK_TARGET:-}" && -e "$APK_TARGET" ]]; then
      echo "fastUpdate: removing unpublished APK" >&2
      rm -f -- "$APK_TARGET" || rollback_failed=1
    fi

    if ((MANIFEST_UPDATED)); then
      restore_backup "$MANIFEST_BACKUP" "$MANIFEST_FILE" "previous update manifest" || rollback_failed=1
    else
      discard_backup "$MANIFEST_BACKUP" || rollback_failed=1
    fi

    if ((SOURCE_UPDATE_STARTED)); then
      restore_backup "$PUBSPEC_BACKUP" "$PUBSPEC_FILE" "previous pubspec version" || rollback_failed=1
      restore_backup "$SERVICE_BACKUP" "$SERVICE_FILE" "previous in-app version" || rollback_failed=1
    else
      discard_backup "$PUBSPEC_BACKUP" || rollback_failed=1
      discard_backup "$SERVICE_BACKUP" || rollback_failed=1
    fi
  fi

  ((rollback_failed == 0)) || echo "fastUpdate: rollback was incomplete; inspect the files above" >&2
  exit "$exit_code"
}

IFS=$'\t' read -r OLD_PUBSPEC_VERSION old_pubspec_code OLD_VERSION_NAME OLD_VERSION_CODE old_manifest_name old_manifest_code < <(read_version_state)

today="$(TZ=Asia/Ho_Chi_Minh date +%y%m%d)"
daily_number=0
for version_name in "$OLD_VERSION_NAME" "$old_manifest_name"; do
  if [[ "$version_name" =~ ^${today}\.([1-9][0-9]*)$ ]]; then
    candidate="${BASH_REMATCH[1]}"
    ((10#$candidate > daily_number)) && daily_number=$((10#$candidate))
  fi
done
for apk_path in "$RELEASES_DIR"/money_manager-"$today".*.apk; do
  [[ -e "$apk_path" ]] || continue
  apk_filename="${apk_path##*/}"
  if [[ "$apk_filename" =~ ^money_manager-${today}\.([1-9][0-9]*)\.apk$ ]]; then
    candidate="${BASH_REMATCH[1]}"
    ((10#$candidate > daily_number)) && daily_number=$((10#$candidate))
  fi
done
daily_number=$((daily_number + 1))
NEW_VERSION_NAME="${today}.${daily_number}"

max_code=0
for version_code in "$old_pubspec_code" "$OLD_VERSION_CODE" "$old_manifest_code"; do
  ((10#$version_code > max_code)) && max_code=$((10#$version_code))
done
NEW_VERSION_CODE=$((max_code + 1))
date_based_code=$((10#$today * 1000 + daily_number))
((date_based_code > NEW_VERSION_CODE)) && NEW_VERSION_CODE=$date_based_code
((NEW_VERSION_CODE < 2100000000)) || die "Next Android versionCode is too large"
NEW_PUBSPEC_VERSION="${today}.${daily_number}.0+${NEW_VERSION_CODE}"

if [[ -z "$NOTES" ]]; then
  NOTES="LAN update ${NEW_VERSION_NAME}."
fi

APK_FILENAME="money_manager-${NEW_VERSION_NAME}.apk"
APK_SOURCE="$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
APK_TARGET="$RELEASES_DIR/$APK_FILENAME"
LOCAL_BASE_URL="http://127.0.0.1:${PORT}"

echo "Release label: ${NEW_VERSION_NAME}"
echo "Flutter version: ${NEW_PUBSPEC_VERSION}"
echo "Android versionCode: ${NEW_VERSION_CODE}"

if ((DRY_RUN)); then
  echo "Dry run only: no files were changed and no backend was started."
  exit 0
fi

[[ ! -e "$APK_TARGET" ]] || die "Refusing to overwrite an existing release APK: $APK_TARGET"

mkdir -p "$DATA_DIR" "$RELEASES_DIR"
exec 9>"$LOCK_FILE"
flock -n 9 || die "Another fastUpdate.sh process is already running"
trap restore_release_on_failure EXIT

PUBSPEC_BACKUP="$(mktemp "$PUBSPEC_FILE.fast-update.XXXXXX")"
SERVICE_BACKUP="$(mktemp "$SERVICE_FILE.fast-update.XXXXXX")"
MANIFEST_BACKUP="$(mktemp "$RELEASES_DIR/.latest.json.fast-update.XXXXXX")"
cp -p -- "$PUBSPEC_FILE" "$PUBSPEC_BACKUP"
cp -p -- "$SERVICE_FILE" "$SERVICE_BACKUP"
cp -p -- "$MANIFEST_FILE" "$MANIFEST_BACKUP"

SOURCE_UPDATE_STARTED=1
apply_versions "$OLD_PUBSPEC_VERSION" "$OLD_VERSION_NAME" "$OLD_VERSION_CODE" "$NEW_PUBSPEC_VERSION" "$NEW_VERSION_NAME" "$NEW_VERSION_CODE"

flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
node --check "$BACKEND_DIR/server.js"
git diff --check -- pubspec.yaml lib/src/services.dart
flutter build apk --debug --build-name "$NEW_VERSION_NAME" --build-number "$NEW_VERSION_CODE"

[[ -s "$APK_SOURCE" ]] || die "Expected APK was not produced: $APK_SOURCE"
TMP_APK="$(mktemp "$RELEASES_DIR/.${APK_FILENAME}.fast-update.XXXXXX")"
cp "$APK_SOURCE" "$TMP_APK"
mv -f -- "$TMP_APK" "$APK_TARGET"
TMP_APK=""
APK_TARGET_CREATED=1

write_manifest() {
  node --input-type=module - "$MANIFEST_FILE" "$NEW_VERSION_NAME" "$NEW_VERSION_CODE" "$APK_FILENAME" "$NOTES" <<'NODE'
import fs from 'node:fs';

const [manifestPath, versionName, versionCode, apkFile, notes] = process.argv.slice(2);
const manifest = {versionName, versionCode: Number(versionCode), apkFile, notes};
const tempPath = `${manifestPath}.fast-update-${process.pid}.tmp`;
fs.writeFileSync(tempPath, `${JSON.stringify(manifest, null, 2)}\n`);
fs.renameSync(tempPath, manifestPath);
NODE
}

write_manifest
MANIFEST_UPDATED=1

backend_healthy() {
  local response
  response="$(curl --fail --silent --show-error --max-time 2 "$LOCAL_BASE_URL/api/health")" || return 1
  printf '%s' "$response" | node --input-type=module -e 'import fs from "node:fs"; const value = JSON.parse(fs.readFileSync(0, "utf8")); if (value.ok !== true || value.service !== "money-manager-backend") process.exit(1);'
}

port_is_in_use() {
  ss -ltnH | awk -v port="$PORT" '$4 ~ (":" port "$") { found = 1 } END { exit !found }'
}

if backend_healthy; then
  echo "Backend is already running on port ${PORT}."
elif port_is_in_use; then
  die "Port ${PORT} is occupied by a process that is not this backend"
else
  if [[ ! -d "$BACKEND_DIR/node_modules/express" ]]; then
    (cd "$BACKEND_DIR" && npm install)
  fi
  echo "Starting backend on port ${PORT}..."
  (
    cd "$BACKEND_DIR"
    nohup env PORT="$PORT" npm start >>"$LOG_FILE" 2>&1 &
    echo "$!" >"$PID_FILE"
  )
  for _ in $(seq 1 30); do
    backend_healthy && break
    sleep 0.5
  done
  backend_healthy || die "Backend did not become healthy. See $LOG_FILE"
fi

update_json="$(curl --fail --silent --show-error --max-time 5 "$LOCAL_BASE_URL/api/update/latest")"
printf '%s' "$update_json" | node --input-type=module -e 'import fs from "node:fs"; const [name, code, file] = process.argv.slice(1); const value = JSON.parse(fs.readFileSync(0, "utf8")); if (value.versionName !== name || value.versionCode !== Number(code) || value.apkUrl !== `/releases/${encodeURIComponent(file)}`) process.exit(1);' "$NEW_VERSION_NAME" "$NEW_VERSION_CODE" "$APK_FILENAME" || die "Backend returned an unexpected update manifest"
curl --fail --silent --show-error --range 0-0 --output /dev/null "$LOCAL_BASE_URL/releases/$APK_FILENAME" || die "Backend cannot serve the published APK"

RELEASE_SUCCEEDED=1
trap - EXIT
discard_backup "$PUBSPEC_BACKUP" || true
discard_backup "$SERVICE_BACKUP" || true
discard_backup "$MANIFEST_BACKUP" || true
PUBSPEC_BACKUP=""
SERVICE_BACKUP=""
MANIFEST_BACKUP=""

detect_lan_ip() {
  if [[ -n "${LAN_IP:-}" ]]; then
    printf '%s\n' "$LAN_IP"
    return
  fi
  hostname -I | tr ' ' '\n' | awk '$1 ~ /^[0-9]+\./ && $1 !~ /^(127|169\.254)\./ { print; exit }'
}

lan_ip="$(detect_lan_ip)"
[[ -n "$lan_ip" ]] || lan_ip="<IP-LAN-MAY-CHAY>"

echo
echo "Published ${NEW_VERSION_NAME} (versionCode ${NEW_VERSION_CODE})."
echo "Backend URL: http://${lan_ip}:${PORT}"
echo "On Android: Account > save Backend URL > Check for update."
echo "The APK is debug-signed; it can update only an app installed with the same signing key."
