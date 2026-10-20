# Local dictation validation — 2026-10-20

The final executable source passed the available Windows-hosted automated
checks. Phone microphone audio is recognized on the phone; final text is typed
through Bluetooth HID without a computer receiver. Desktop microphone
recognition uses the same local engine. Dictation saves no audio recordings and
never automatically replays failed or uncertain partial output.

## Automated results

| Suite | Passed | Skipped | Measured Dart line coverage |
| --- | ---: | ---: | ---: |
| Phone app, including screenshot tests | 103 | 0 | 3574 / 4568 (78.24%) |
| Desktop Companion, including screenshot tests | 25 | 0 | 1090 / 1765 (61.76%) |
| Shared protocol | 6 | 0 | 304 / 351 (86.61%) |
| Local dictation engine, including real SenseVoice FFI | 20 | 0 | 528 / 657 (80.37%) |
| Android Kotlin HID and installer validation | 16 | 0 | Not instrumented |

All **170 tests** passed. All four package analyses passed, and all 15
changed/new Dart files passed formatting checks. Aggregate owned Dart `lib`
coverage is **5496 / 7341 lines (74.87%)**, deduplicated across packages. These
are measured results, without an arbitrary threshold; native C++, Swift and
Kotlin coverage is outside the LCOV figure.

Separate PowerShell fixture suites passed for Windows install/uninstall and
rollback, installer staging/publication failures, and APK ZIP verification.
They cover unmanaged/tampered-file preservation, invalid manifests, version,
filename, size/hash constraints, missing packages, unlisted nested content,
duplicate ZIP entries, idempotent staging and release-directory switching.
A disposable debug APK was built with tiny test installer fixtures; the
catalog and both nested assets matched their expected sizes and SHA-256 values.
The fixture APK was removed and assets/pubspec restored. The deliverable APK
was independently checked to contain no test installers or generated catalog.

Phone regressions cover printable ASCII, mixed BMP Unicode, unsupported/overlong
phrase rejection before output, fixed Windows Alt/keypad sequences, modifier
release, exclusive batches, bounded queues, host A → B → A invalidation, late
cleanup across panels, output errors without replay and updated first-use help.
Installer tests cover actual MethodChannel contracts, metadata/receipt checks,
folder selection, verified-success/error states and locking folder changes
during export.

The real SenseVoice test used verified local model files and existing 16 kHz
WAV fixtures. Its `zh → en → zh → en → en` results matched fresh recognizers.
This confirms native loading and language replacement, rather than live
microphone quality or latency. Cohere management/selection uses deterministic
fixtures; real Cohere inference was not run.

## Builds and current computer installation

- The final Android debug APK built successfully. Application ID/namespace is
  `com.lumiaiq.smartkey`; the public name remains **LumiaKey**. The prior
  identity change also updated macOS/Linux IDs and Windows product resources.
- Windows Release was built and smoke-checked during the preceding identity
  change. Desktop/shared-engine executable source is unchanged in this follow-up.
  That bundle was installed in `%LOCALAPPDATA%\Programs\LumiaKey`, with a
  current-user Start Menu shortcut and uninstall helper. All 23 application
  files matched their SHA-256 inventory, and the tray process launched.
- Existing verified SenseVoice model/token files were copied into LumiaKey's
  own application-support cache. No download, microphone capture, clipboard
  operation, target text insertion or Windows HexNumpad setting change occurred.
  The installed uninstall helper was updated to the tested version. Uninstall
  preserves separate preferences/models and refuses unmanaged or corrupted
  program-directory contents.
- Tagged release CI now builds Windows/macOS installers before Android, embeds
  artifacts from that exact run, and checks the built APK's catalog and installer
  hashes before upload. No tag/release was created here; the remote macOS/signing
  pipeline has not run for this change. Development builds without release
  packages explicitly report them as unavailable.

## Approved Windows Unicode setup after validation

After the validation above, the user approved the one-time Windows HexNumpad
setup for this PC. `HKCU\Control Panel\Input Method\EnableHexNumpad` was
created as `REG_SZ` with value `1`, and an independent registry readback
confirmed the value and type. It was absent before setup. The evidence record
is `coverage/windows-hexnumpad-setting.json`; it records that neither sign-out
nor reboot was performed. This is a user-approved system setting, not an
application change, and the app's default output profile remains US ASCII.

Windows still requires sign-out or reboot before HexNumpad behavior can be
accepted. Typing Unicode through the real LumiaKey Bluetooth HID path into a
compatible foreground application also remains pending. No end-to-end Windows
Unicode input claim is made from the registry readback alone.

Flutter 3.44.2 / Dart 3.12.2 and installed Windows/Android toolchains were used.
The exFAT checkout cannot provide Windows plugin symlinks and causes Kotlin
cache failures, so builds/tests ran in a short NTFS source copy. Executable,
configuration and test hashes were checked against the checkout.

## Screenshot report

Seven screenshot widget tests, included above, produced **58 PNGs** with
metadata: **36 phone** and **22 desktop** captures. They cover public screens,
normal/narrow desktop settings, editing/import dialogs, first-use explanations,
Bluetooth readiness, models/languages/output profiles, Windows Unicode setup,
listening/errors, and installer catalog/verification/export states. Captures
check content, PNG dimensions and absence of Flutter/layout exceptions. No
committed pixel baselines are used.

New/changed states were visually reviewed with CJK and symbol fonts; unchanged
desktop states were reviewed in the preceding validation. The run fixed lazy
list screenshot scrolling with larger fonts and an actual stale verification
status after successful export. These are deterministic Flutter widget renders
with injected dependencies, not native macOS or physical-device screenshots.

Generated artifacts, excluded from Git:

- `build/ui_screenshots-bluetooth/index.html` — searchable offline gallery.
- `build/ui_screenshots-bluetooth.zip` — HTML, PNGs and metadata.
- `coverage/summary.json`, merged/per-package LCOV, Android JUnit XML,
  source/installation evidence and validation logs.
- `build/artifacts/LumiaKey-Android-debug.apk` and the previously verified
  `build/artifacts/LumiaKey-Windows-portable.zip`.

The full Dart/build run is in `final-bluetooth-validation.log`; its native phase
initially exposed two incorrect test expectations. After correcting only those
native test fixtures, all 16 Kotlin tests passed in `final-kotlin-validation.log`.
Coverage/gallery aggregation and compiled APK embedding checks completed
afterwards. Production code did not change between the passing Dart/build run
and native rerun.

## Reproduction and acceptance boundaries

Run `scripts/validate_local_dictation.ps1 -BuildAndroid` on a supported Windows
filesystem, optionally supplying `-PubCache`. Real FFI tests also need
`LOCAL_DICTATION_MODEL_DIR`, `LOCAL_DICTATION_ZH_WAV`, `LOCAL_DICTATION_EN_WAV`
and `LOCAL_DICTATION_NATIVE_DIR`; all were supplied. Optional
`SMARTKEYS_SCREENSHOT_FONT` and `SMARTKEYS_SCREENSHOT_SYMBOL_FONT` supply fonts.
Installer test commands are in `GITHUB_RELEASES.md` and `WINDOWS_INSTALL.md`.

A Moto g play was detected by ADB, but no new phone app was installed and no
live microphone or Bluetooth target-input test was performed. Windows Unicode
mode requires manual HexNumpad setup, Num Lock and a compatible application;
actual input acceptance and native macOS build/permissions remain separate.
USB export uses a local SAF folder and MTP; it does not expose a USB
mass-storage drive or Windows drive letter.
