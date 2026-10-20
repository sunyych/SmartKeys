# Current and historical local dictation validation — 2026-10-20

## Current verification — 1.2.1+3

All available 1.2.1+3 automated checks passed. Four Dart packages passed
analysis and their complete suites with measured coverage; Android Kotlin unit
tests and the screenshot suites also passed. All 10 changed Dart files passed
format checks.

| Suite | Passed | Skipped | Measured Dart line coverage |
| --- | ---: | ---: | ---: |
| Phone app, including screenshot tests | 106 | 0 | 3695 / 4705 (78.53%) |
| Desktop Companion, including screenshot tests | 26 | 0 | 1090 / 1765 (61.76%) |
| Shared protocol | 6 | 0 | 304 / 351 (86.61%) |
| Local dictation engine, including SenseVoice zh/en fixtures | 20 | 0 | 528 / 657 (80.37%) |
| Android Kotlin tests (13 HID, 3 installer) | 16 | 0 | Not instrumented |

That is **158 Dart tests plus 16 Kotlin tests (174 total)**. Aggregate owned
Dart `lib` coverage is **5617 / 7478 lines (75.11%)**. Native C++, Swift and
Kotlin coverage is not measured by these LCOV figures. The SenseVoice fixture
sequence covered Chinese and English recognizer replacement. All four package
analyses passed, as did the 10 changed-file Dart formatting checks. An initial
layout-overflow and stop-guard fixture issue was corrected; the final run had
no remaining failures.

The final phone and Desktop tests also cover exact accented/CJK text transport,
legacy Bluetooth output preference migration, Desktop host/delivery-failure
cancellation, and no fallback or retry after insertion rejection.

The screenshot suites produced **58 captures** (36 phone, 22 desktop) and the
offline gallery at `build/ui_screenshots-english/index.html`. The root agent
visually reviewed the English-only and Desktop-ready panel states. These are
deterministic Flutter renders, not physical-device screenshots.

The Android split debug build succeeded for ARM64. The installed APK is
`com.lumiaiq.smartkey`, version **1.2.1**, version code **2003**, app label
**LumiaKey**, SHA-256
`2905CB31E79576E63CE1FFC72E867DA5693FE11FDB4DFEF167104A031F00A184`. It
contains no fake installer assets or generated installer catalog; only the
tracked README installer asset is present. On a Moto g play (2024), paired ADB
over TLS/LAN returned `Success` for `install-r`, and `am start` returned
`Status: ok` with PID 24557. The prior plural-package app remains installed as
a separate package. Existing SenseVoice model and token hashes were unchanged.

The Windows Release build and installer upgrade to **1.2.1+3** succeeded. All
23 managed application files matched their SHA-256 inventory, the app launched
(PID 58900), and the existing model SHA-256 remained unchanged.

No live microphone-to-target typing acceptance was performed. No native macOS
build or release CI run is claimed. These limits are separate from the passing
automated checks and successful Android/Windows installation evidence.

## Historical snapshot — 2026-10-20

**Status:** This snapshot records validation performed before the current
output-policy amendment. Its recorded test/build evidence remains historical
evidence for that source revision. Its Bluetooth Unicode/HexNumpad guidance
and phone-without-Desktop multilingual-output claims are superseded. Current
Bluetooth dictation is English-only; multilingual phone output requires an
explicit LumiaKey Desktop receiver. Bluetooth output requires a US keyboard
layout. HexNumpad is not a supported mode or a current prerequisite. Current
1.2.1+3 results are recorded above.

For that historical executable source, the available Windows-hosted automated
checks passed. Phone microphone audio was recognized on the phone; final text
was typed through Bluetooth HID without a computer receiver. Desktop microphone
recognition used the same local engine. Dictation saved no audio recordings and
did not automatically replay failed or uncertain partial output.

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

## Historical Windows Unicode setup record (superseded)

After the validation above, the user approved a one-time Windows HexNumpad
setup for this PC. `HKCU\Control Panel\Input Method\EnableHexNumpad` was
created as `REG_SZ` with value `1`, and an independent registry readback
confirmed the value and type. It was absent before setup. The evidence record
is `coverage/windows-hexnumpad-setting.json`; it records that neither sign-out
nor reboot was performed. This is historical machine-state evidence only. The
current app does not use HexNumpad, and this value is not required for current
dictation. LumiaKey does not edit or remove it.

For the historical HexNumpad mode, Windows would still have required sign-out
or reboot before behavior could be accepted. Typing Unicode through the real
LumiaKey Bluetooth HID path into a compatible foreground application also
remained pending. No end-to-end Windows Unicode input claim was made from the
registry readback alone; HexNumpad is no longer a current output mode.

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
live microphone or Bluetooth target-input test was performed. Those limits
describe this historical run. They do not validate the current Desktop text
route or ARM64 install/reinstall.
USB export uses a local SAF folder and MTP; it does not expose a USB
mass-storage drive or Windows drive letter.

## Current output-policy validation status

The package version is `1.2.1+3` in both phone and Desktop manifests. Current
automated results, screenshot review, Android ARM64 install and Windows
installer upgrade are recorded at the top of this document. Live microphone
and target-typing acceptance and native macOS build/permissions remain
unverified; no claim is made for those checks.
