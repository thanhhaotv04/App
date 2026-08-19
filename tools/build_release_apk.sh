#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SLUG="task-reminder"
DEFAULT_APK="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
NAMED_APK="$ROOT_DIR/build/app/outputs/flutter-apk/app-release-$APP_SLUG.apk"
BACKEND_APK="$ROOT_DIR/backend/releases/app-release-$APP_SLUG.apk"

cd "$ROOT_DIR"
flutter build apk --release

cp "$DEFAULT_APK" "$NAMED_APK"
cp "$NAMED_APK" "$BACKEND_APK"

echo "Release APK: $NAMED_APK"
echo "Backend APK: $BACKEND_APK"
