#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Run after flutter build apk --release. A debug unit test cannot catch this:
# OsmAnd puts the original Parcelable class name into its cross-app Bundle.
rg -q '^net\.osmand\.aidlapi\.map\.ALatLon -> net\.osmand\.aidlapi\.map\.ALatLon:$' \
  build/app/outputs/mapping/release/mapping.txt
printf '%s\n' 'PASS: OsmAnd AppInfo Parcelable retains its cross-app wire name.'
