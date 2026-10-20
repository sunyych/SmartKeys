# Local dictation validation — 2026-10-20

The final source passed the available Windows-hosted validation. Phone audio is
recognized on the phone; the authenticated LAN request carries final text only.
Desktop microphone recognition uses the same local engine. Neither path writes
audio recordings or queues failed phrases for automatic replay.

## Automated results

| Suite | Passed | Skipped | Measured Dart line coverage |
| --- | ---: | ---: | ---: |
| Phone app, including screenshot tests | 79 | 0 | 3121 / 4061 (76.85%) |
| Desktop Companion, including screenshot tests | 25 | 0 | 1090 / 1765 (61.76%) |
| Shared protocol | 6 | 0 | 304 / 351 (86.61%) |
| Local dictation engine, including real SenseVoice FFI | 20 | 0 | 528 / 657 (80.37%) |
| Android Kotlin encoder unit tests | 8 | 0 | Not instrumented |

All **138 tests** passed. All four Dart/Flutter packages passed static analysis.
Formatting checks passed for all 33 changed/new Dart files. Aggregate coverage
of owned Dart `lib` source is **5043 / 6834 lines (73.79%)**, deduplicated across
the four packages. These are measured results, not a claim of 100% coverage;
native C++, Swift and Kotlin coverage is outside the LCOV figure.

The regression tests exercise bounded audio segmentation, cancellation and
shutdown races, final-phrase flush, microphone/wakelock failures, host switching,
same-host manifest refresh, authentication, request bounds, serialized Unicode
delivery, failed/partial insertion tombstones, first-use consent, and UI model
and language selection. Existing application, shortcut and protocol suites were
retained.

The real SenseVoice test ran against verified local model files and 16 kHz WAV
fixtures. Its `zh → en → zh → en → en` outputs matched fresh language-specific
recognizers. It validates native loading and recognizer replacement, rather than
measuring recognition accuracy or live microphone latency.

## Builds and packaged checks

- Android debug APK built successfully from the final phone/shared source.
- Windows Release built successfully with the final desktop UI fixes.
- The Windows bundle contains ONNX Runtime, sherpa-onnx and microphone plugins.
  Its ONNX Runtime SHA-256 matched the resolved dependency.
- The final Windows executable was launched hidden and checked through actual
  UDP discovery and HTTP: unauthenticated manifest `403`, authenticated manifest
  `200`, invalid dictation `400`, and `local-dictation-v1` advertised. The
  process was closed afterwards; this check captured no microphone audio and
  injected no text into another application.

Flutter 3.44.2 / Dart 3.12.2 and the installed Windows/Android toolchains were
used. The checkout is on exFAT, which cannot provide Flutter's required Windows
plugin symlinks and causes Kotlin cache errors. Builds/tests therefore ran in a
short NTFS temporary source copy. All source file hashes matched the checkout
after validation; generated outputs were copied back to ignored directories.

## Screenshot report

Six screenshot widget tests (already included in the counts above) produced
**46 PNGs** with metadata: 24 phone captures and 22 desktop captures. Coverage
includes all public phone screens, the seven desktop settings sections at normal
and narrow widths, editing/import dialogs, first-use explanations, and dictation
model/language/download/listening/error states. Captures assert expected content,
valid image dimensions and absence of Flutter/layout exceptions. They do not use
committed pixel baselines.

All captures were visually inspected; the final report uses real text/icon fonts
with Chinese and symbol fallback. Screenshot validation found and fixed a real
desktop model-selector `setState` error. These are deterministic Flutter widget
renders with injected dependencies, not physical-device or macOS screenshots.

Generated artifacts, excluded from Git:

- `build/ui_screenshots/index.html` — offline gallery with filters and image zoom.
- `build/ui_screenshots.zip` — portable gallery, images and metadata.
- `coverage/summary.json`, `coverage/local-dictation-merged.lcov`, per-package
  LCOV reports, Android JUnit XML, and full validation/build logs.
- `build/artifacts/LumiaKey-Android-debug.apk` and
  `build/artifacts/LumiaKey-Windows-portable.zip`.

## Reproduction and remaining acceptance

Run `scripts/validate_local_dictation.ps1 -BuildAndroid` on a supported Windows
filesystem, optionally supplying `-PubCache`. The real FFI test additionally
requires `LOCAL_DICTATION_MODEL_DIR`, `LOCAL_DICTATION_ZH_WAV`,
`LOCAL_DICTATION_EN_WAV` and `LOCAL_DICTATION_NATIVE_DIR`; without them it reports
an explicit skip. This validation supplied all four. Optional
`SMARTKEYS_SCREENSHOT_FONT` and `SMARTKEYS_SCREENSHOT_SYMBOL_FONT` provide local
CJK and symbol fonts for the generated gallery. No fonts, model files, WAVs,
screenshots, HTML reports or build products were added to Git.

No physical Android phone was connected. Live phone/desktop microphone quality,
latency, actual cursor insertion into target applications and macOS native
build/permissions still need device acceptance. Cohere model management and
selection use deterministic fixtures here; a real Cohere inference run was not
performed. Tagged release CI retains native macOS packaging and uploads test
reports separately from release installers.

## Application identity follow-up

The public app name is now **LumiaKey**. Android application ID/namespace,
macOS bundle ID and Linux application ID are **`com.lumiaiq.smartkey`**.
Android Kotlin main/test package declarations and source directories were moved
together. macOS product/scheme/test-host references and release artifact paths
were updated for `LumiaKey.app`. Windows product resources, window/tray titles
and installer display name use LumiaKey; its existing installer upgrade GUID
and executable filename remain compatible.

The complete validation was rerun after the identity change: 138 tests passed,
four package analyses passed, coverage remained 73.79%, 46 screenshot renders
were regenerated, and Android debug / Windows Release builds passed. APK
badging confirmed package `com.lumiaiq.smartkey`, label `LumiaKey` and launcher
`com.lumiaiq.smartkey.MainActivity`. Windows executable ProductName and
FileDescription both read `LumiaKey`. macOS plist/scheme XML was parsed, but no
native macOS build was performed. Generated identity evidence is in
`coverage/application-identity.json`.
