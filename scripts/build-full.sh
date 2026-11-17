#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
platform="${1:-apk}"
shift || true
case "$platform" in
  apk|appbundle|ios|macos|windows|linux) flutter build "$platform" "$@" ;;
  *) echo "Usage: $0 {apk|appbundle|ios|macos|windows|linux} [flutter build options...]" >&2; exit 2 ;;
esac
