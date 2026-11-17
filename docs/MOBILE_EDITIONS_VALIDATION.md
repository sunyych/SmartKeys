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
