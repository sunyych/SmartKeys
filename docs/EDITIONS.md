# LumiaKey editions

This is the current 1.5 integration architecture. The shared-package Android
`lite` flavor and `lib/main_lite.dart` remain historical 1.4 compatibility
source and are not the independent Lite product. See
[the 1.4 validation record](MOBILE_EDITIONS_VALIDATION.md) for those older builds.

LumiaKey ships as two independently built products in this repository.

| Edition | App project | Platforms | Includes |
| --- | --- | --- | --- |
| Full | repository root | Android, iOS, Windows, macOS, Linux | Desktop-connected controls, profiles, setup, companion features, and full app integrations |
| Bluetooth Lite | `apps/bluetooth` | Android only | Bluetooth HID keyboard, mouse/touchpad, media controls, and manually edited shortcuts stored locally on the phone |

Bluetooth Lite has its own Flutter package, Android Gradle project, `applicationId` (`com.lumiaiq.bluetoothlite`), launcher, manifest, and entry point. It does not depend on root Flutter packages, desktop companion code, community server code, account services, or the local dictation package. Its manifest declares nearby Bluetooth permissions only; it does not request Internet or microphone access. The Android HID controller keeps the paired-device flow, runtime permission requests, host switching, connection errors, and key release behavior.

Full retains the confirmed twelve-cell, four-column by three-row landscape-only
mobile surface. The handoff's older eight-slot/portrait design does not replace
that choice. Lite retains its standalone keyboard, mouse, media and local
shortcut screens. Its General, ChatGPT and Chrome profiles are edited on the
phone; opening a profile never launches an app on the computer. Default key
combinations use Ctrl; edit their modifiers for a computer that uses Command.

The independent Lite package coexists with Full and with the older
`com.lumiaiq.smartkey.lite` installation. It does not remove, replace or read the
private data of either app. A debug APK is a development-signed validation
artifact. Release signing still requires all four Android signing environment
values; an unsigned release APK is not an installable release delivery.

## Build

```sh
./scripts/build-full.sh apk --release
./scripts/build-full.sh ios --no-codesign
./scripts/build-full.sh linux --release
./scripts/build-bluetooth-lite.sh apk --debug
# Windows: scripts/build_lite.ps1 -Configuration debug
# Independent export: scripts/build.sh apk --debug, from the Lite directory
```

Full version tags retain the `vMAJOR.MINOR.PATCH` convention, while a future
independent Lite release can use `bluetooth-vMAJOR.MINOR.PATCH`. This integration
does not create or push tags or Releases. The Lite workflow builds artifacts
from a sparse checkout containing only `apps/bluetooth`; it asserts Full's
parent `pubspec.yaml` and `lib/` are absent before verification. The exported
Lite also includes a workflow that runs with Lite as the repository root.
Linux runtime controls use X11; unsupported Wayland automation must not be
described as validated Linux input support.

## Export source folders

`./scripts/export-editions.sh /path/to/new-export-directory` exports Full and Lite into separate source folders without creating Git repositories or remotes. The destination must be new and outside this repository. It refuses to overwrite an existing destination, excludes generated build output and signing/local configuration files, and includes a self-contained Lite build/test/screenshot workflow.

On Windows use `python scripts/export_editions.py C:\path\to\new-export`.
The Python standard-library exporter needs no rsync. Source links and Windows
junctions/reparse points are rejected, and copying completes in a fresh staging
directory before claiming the destination. Full exports omit `apps/bluetooth`,
the independent Lite workflow/build entry points, and generated Desktop installer
payloads. Only the two checked-in Rust test fixtures
`community_server/tests/fixtures/test-rsa-{private,public}.pem` are allowed through
the PEM filter; all other PEM/private signing files remain excluded.

## Shortcuts

Lite shortcuts are user-authored combinations from the in-app editor and persisted in Android app preferences. They are local to that installation and are not synchronized or downloaded. The screens do not include setup wizards, launchers, companion management, dashboards, or account features.

The new profile store preserves a WIP `lite.shortcuts` list as a Custom profile;
it does not delete the old preference. A failed save leaves the previously
displayed/persisted shortcuts intact and shows an error. Native and Flutter
background handling release input and clear pending modifiers.

Run `python scripts/check_isolation.py --apk build/app/outputs/flutter-apk/app-debug.apk`
inside Lite after building. It checks the actual APK manifest/package and rejects
Full-only assets/native libraries, in addition to source, lockfile and plugin
boundaries. Final execution evidence is recorded separately after running the
current checks; the WIP handoff is not build-validation evidence.
