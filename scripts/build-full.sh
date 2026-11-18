#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo"
platform="${1:-apk}"
shift || true
case "$platform" in
  apk|appbundle) flutter build "$platform" --flavor regular --target lib/main.dart --dart-define=LUMIAKEY_EDITION=regular "$@" ;;
  ios) flutter build ios --target lib/main.dart --dart-define=LUMIAKEY_EDITION=regular "$@" ;;
  macos|windows|linux) cd "$repo/desktop_companion"; flutter build "$platform" "$@" ;;
  *) echo "Usage: $0 {apk|appbundle|ios|macos|windows|linux} [flutter build options...]" >&2; exit 2 ;;
esac
