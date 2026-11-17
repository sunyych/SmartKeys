#!/usr/bin/env bash
set -euo pipefail
lite="$(cd "$(dirname "$0")/.." && pwd)"
if rg -n 'local_dictation|lumiakeys_protocol|google_sign_in|image_picker|file_picker|path_provider' "$lite/pubspec.yaml"; then
  echo 'Forbidden dependency in Bluetooth Lite pubspec' >&2; exit 1
fi
if rg -n 'android.permission.(INTERNET|RECORD_AUDIO)' "$lite/android/app/src/main/AndroidManifest.xml"; then
  echo 'Internet or microphone permission in Bluetooth Lite manifest' >&2; exit 1
fi
application_id="$(sed -n 's/.*applicationId = "\([^"]*\)".*/\1/p' "$lite/android/app/build.gradle.kts")"
[[ "$application_id" == 'com.lumiaiq.bluetoothlite' ]] || { echo "Unexpected Lite applicationId: $application_id" >&2; exit 1; }
echo 'Bluetooth Lite dependencies, permissions, and Android package are isolated.'
