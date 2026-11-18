#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo/apps/bluetooth"
platform="${1:-apk}"
shift || true
if [[ "$platform" != apk ]]; then
  echo "Bluetooth Lite is Android-only; use: $0 apk [flutter build options...]" >&2
  exit 2
fi
flutter build apk "$@"
