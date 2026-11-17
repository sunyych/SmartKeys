#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:-apk}"
shift || true
[[ "$platform" == apk ]] || { echo "Bluetooth Lite supports Android APK only." >&2; exit 2; }
flutter build apk "$@"
