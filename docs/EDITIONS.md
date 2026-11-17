# LumiaKey editions

LumiaKey ships as two independently built products in this repository.

| Edition | App project | Platforms | Includes |
| --- | --- | --- | --- |
| Full | repository root | Android, iOS, Windows, macOS, Linux | Desktop-connected controls, profiles, setup, companion features, and full app integrations |
| Bluetooth Lite | `apps/bluetooth` | Android only | Bluetooth HID keyboard, mouse/touchpad, media controls, and manually edited shortcuts stored locally on the phone |

Bluetooth Lite has its own Flutter package, Android Gradle project, `applicationId` (`com.lumiaiq.bluetoothlite`), launcher, manifest, and entry point. It does not depend on root Flutter packages, desktop companion code, community server code, account services, or the local dictation package. Its manifest declares nearby Bluetooth permissions only; it does not request Internet or microphone access. The Android HID controller keeps the paired-device flow, runtime permission requests, host switching, connection errors, and key release behavior.

## Build

```sh
./scripts/build-full.sh apk --release
./scripts/build-full.sh ios --no-codesign
./scripts/build-full.sh linux --release
./scripts/build-bluetooth-lite.sh apk --debug
```

Full releases retain the existing `vMAJOR.MINOR.PATCH` tags. The Full Linux workflow builds the desktop bundle and uploads a tar.gz workflow artifact. Linux runtime controls use X11; `xdotool` is needed for keyboard/mouse/foreground actions, while `playerctl` and `pactl` (Ubuntu package `pulseaudio-utils`) enable optional media/audio actions. Bluetooth Lite listens only to `bluetooth-vMAJOR.MINOR.PATCH` and builds/tests `apps/bluetooth` in isolation; it does not package desktop assets. Tag builds require the existing Android signing secrets and upload an APK as a workflow artifact; manual workflow runs build a debug validation APK. These workflows upload run artifacts and do not create a GitHub Release.

## Export source folders

`./scripts/export-editions.sh /path/to/new-export-directory` exports Full and Lite into separate source folders without creating Git repositories or remotes. The destination must be new and outside this repository. It refuses to overwrite an existing destination, excludes generated build output and signing/local configuration files, and includes a self-contained Lite build/test/screenshot workflow.

## Shortcuts

Lite shortcuts are user-authored combinations from the in-app editor and persisted in Android app preferences. They are local to that installation and are not synchronized or downloaded. The screens do not include setup wizards, launchers, companion management, dashboards, or account features.
