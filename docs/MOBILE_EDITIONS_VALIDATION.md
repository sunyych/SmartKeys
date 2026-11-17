# LumiaKey 1.4.0 validation

Validation date: 2026-11-17. Mobile and Desktop version: `1.4.0+6`.

## Automated checks

- Mobile static analysis: no issues.
- Mobile complete suite: **281 passed**. This includes real edition-root routing,
  Lite local editing and Bluetooth dispatch, disabled Desktop execution in Lite,
  the Regular twelve-cell layout, overflow pages, connection/session races,
  pointer capability checks, portrait gating, and widget screenshots.
- Desktop complete suite: **70 passed**, including the actual authenticated HTTP
  manifest/action endpoint, twelve-key defaults, custom-layout preservation,
  legacy/platform default migration, fixed media dispatch, and Desktop screenshots.
- Protocol analysis: no issues; complete suite: **20 passed**.
- Local dictation: **24 passed, 1 skipped**. The skipped native SenseVoice test
  needs external speech models, Chinese/English WAV files, and native runtime
  fixtures; this task does not establish recognition accuracy on real audio.
- After making installer assets Regular-only, **14 focused mobile tests passed**
  for installer handling, the Regular root, and Lite editing/transport behavior.
- Android native unit tests: **16 passed for Regular and 16 passed for Lite**,
  with no failures, errors, or skipped cases. This Windows invocation used the
  installed JDK 17 and disabled Kotlin incremental compilation for that process
  to avoid the cache's cross-drive path conversion error:

  ```powershell
  ./android/gradlew.bat -p android :app:testRegularDebugUnitTest :app:testLiteDebugUnitTest '-Pkotlin.incremental=false' '-Pkotlin.compiler.execution.strategy=in-process'
  ```
- Windows Desktop Release **successfully compiled locally** as `1.4.0+6` in the
  NTFS mirror. The temporary drive mapping was removed after the build.

The validation commands and raw logs are in the local `build/` directories.
The Android matrix and Apple/Windows build jobs retain logs and artifacts in
GitHub Actions for the corresponding source commit.

## Hosted build results and delivery

Application source commit: `ec6822302e9c0bed8f71c9b83477e5363536926d`.

- [Android editions and Windows installer](https://github.com/sunyych/SmartKeys/actions/runs/44159767186):
  completed successfully. Both Android builds and their native tests passed;
  the Windows Release build and Setup installer completed successfully.
- [Apple build checks](https://github.com/sunyych/SmartKeys/actions/runs/44159767156):
  completed successfully. Regular iOS compiled and was archived without signing;
  macOS Desktop compiled and produced its DMG.

The downloaded iOS application's actual `Info.plist` reports version `1.4.0`,
build `6`, minimum iOS `15.0`, iPhone and iPad device families, only the two
landscape orientations for both families, and full-screen mode.

Local delivery directory: `build/artifacts/1.4.0/`.

| File | Purpose |
|---|---|
| `LumiaKey-Lite-1.4.0-Android.apk` | Standalone Android Bluetooth edition |
| `LumiaKey-Regular-1.4.0-Android.apk` | Android Desktop-controlled edition |
| `LumiaKey-Desktop-1.4.0-Windows-Setup.exe` | Hosted-build Windows installer |
| `LumiaKey-Desktop-1.4.0-Windows-portable.zip` | Locally compiled Windows portable alternative |
| `LumiaKey-Desktop-1.4.0-macOS.dmg` | Hosted-build macOS Desktop installer |
| `LumiaKey-Regular-1.4.0-iOS-unsigned.zip` | Unsigned iOS build evidence, not an installable IPA |

`SHA256SUMS.txt` and `BUILD-MANIFEST.json` accompany the files. The manifest records
the application source commit, build versions, checks, and hosted evidence;
validation-only documentation commits do not change the packaged application code.

## Android package checks

Both release APKs were successfully built with Flutter 3.44.2 / Dart 3.12.2.
They target API 36, require API 28 or newer, and contain `armeabi-v7a`,
`arm64-v8a`, and `x86_64` native libraries.

- Regular: `com.lumiaiq.smartkey`, display name `LumiaKey`.
- Lite: `com.lumiaiq.smartkey.lite`, display name `LumiaKey Lite`.
- Both report version `1.4.0`, version code `6`.
- Android signature verification passed for both packages. These local APKs use
  the existing debug-key fallback in the release build configuration; they are
  not store-signed release artifacts.
- Lite contains the Bluetooth permissions needed by its HID service. Regular's
  manifest has no Bluetooth permissions and its native activity does not create
  the Bluetooth HID controller.
- Inspection of the actual ZIP entries confirms Lite excludes
  `assets/flutter_assets/assets/desktop_installers/`; Regular retains its
  installer asset directory. Tagged builds prepare real Desktop installers only
  for Regular and publish both Android editions.

The delivered local artifacts include a separate SHA-256 checksum file and build
manifest. Generated installation files are not committed to the repository.

## Visual review and remaining device scope

The real Flutter widget tree was rendered and reviewed at phone landscape
`844×390`, Lite landscape `900×420`, and iPad-size landscape `1180×820`.
Additional widget tests cover phone safe areas and enlarged text. The images
live under `build/ui_screenshots/phone/` and are widget renders, not physical
device screenshots.

The Regular control surface stays at four columns by three rows, with persistent
right touchpad and scrollable left navigation. The phone's built-in long labels
are shortened without overwriting custom names. Images have a loading fallback
and are fully decoded for screenshot verification.

Native orientation declarations and a portrait control gate implement horizontal
use. Device operating systems can override orientation requests, so physical
Android/iPhone/iPad rotation and connection acceptance remain separate checks.

Regular's new General media controls require the updated 1.4 Desktop companion.
The Apple workflow builds the Regular iOS application without signing and creates
a macOS Desktop DMG. An unsigned iOS `.app` ZIP cannot be installed as a signed
IPA; it needs appropriate Apple provisioning/distribution. The macOS package is
not a notarized distribution release, and the Windows installer is not Authenticode
signed.

The Windows source workspace is on exFAT, which cannot create the plugin links
needed by Flutter's Windows desktop build. A temporary NTFS source mirror is used
for local compilation; hosted Windows builds use a normal NTFS checkout. No SDK
source or system policy is changed by this workaround.

## Installed-device follow-up

On 2026-11-17, the delivered Windows Setup installer successfully upgraded the
current computer's Desktop app from `1.3.0+5` to `1.4.0+6`. The existing settings
JSON files were backed up locally before the upgrade. The installed executable's
version, running process, and listening companion service were verified.

The connected Moto G Play 2024 running Android 14 received both Android editions
at version `1.4.0`, build `6`. Regular was upgraded with ADB's data-preserving
reinstall option; Lite was installed separately. Both activities started
successfully on the physical phone.

Regular automatically connected to the upgraded current Windows computer. Its
actual device UI showed the installed application Launchpad, enabled touchpad,
and the twelve General controls in four columns by three rows. Lite's actual UI
showed the three local profiles and the retained fifteen-key control surface.
Lite's optional community setup was skipped and its required Bluetooth Nearby
Devices permissions were granted. Microphone access was not enabled for Lite.

Device screenshots and installation logs remain in local `build/` directories;
device identifiers, network addresses, credentials, and configuration backups are
not committed. This follow-up verifies installation, startup, displayed layouts,
and the Regular-to-Desktop connection. Physical shortcut execution, Bluetooth HID
input delivery, dictation accuracy, and exhaustive rotation checks were not
exercised during this installation.
