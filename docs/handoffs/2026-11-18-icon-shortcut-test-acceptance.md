# Icon and shortcut regression acceptance

Date: 2026-11-18. Branch: `codex/host-switch-pointer-and-sidebar`.

## Changes and evidence

The new tests exposed a real race: a shortcut pressed on host A could be released after host B became ready but before repaint, sending the old tap to B. Regular Home now captures the rendered session and input epoch before accepting a grid shortcut, launcher action or App navigation action. Tests reject stale events and verify fresh input remains usable. Authentication and foreground restrictions remain in place.

| Area | Automated acceptance |
| --- | --- |
| Artwork and OS libraries | All 60 registered PNGs and every supported OS library round-trip through the manifest into Full; warm caches reject altered bytes and wrong identity |
| Full shortcut authority | OS-specific display, no implicit launch, app foreground guards, unassigned zero input, stale host/epoch clicks, fresh input after switch |
| Desktop installation | Real Mac/Linux chords, unsupported OS rejection, artwork/profile atomic persistence failure and retry, actual JSON reload |
| User customization | Edited/deleted/reordered shortcuts and 15-key layouts retained through restart and replacement; sidebar order and explicit empty lists persisted |
| Protocol and permissions | Embedded icons omitted when sync disabled, source metadata preserved, unavailable sidebar references filtered; launch-only apps cannot gain managed shortcut privileges |
| Lite | Delayed and concurrent add-copy persistence, no premature publication, configured private launch keys preserved; unassigned actions produce no Bluetooth input |
| Public platform | All 60 App downloads and 60 legacy icons verified; 17 corrupt/oversize/MIME/base64/identity/hash/redirect/timeout cases rejected; two recovery downloads verified; zero redirect-target requests |
| Input lifecycle | Previous touchpad unload/cancel regressions, two-host HTTP isolation and failure recovery retained |

## Complete local runs

| Suite | Result |
| --- | --- |
| Full | 359 passed; analysis clean |
| Desktop | 159 passed; 1 Linux-only test skipped on Windows; analysis clean |
| Bluetooth Lite | 84 passed; analysis clean |
| Shared protocol | 37 passed |
| Shared diagnostics | 8 passed |
| Shared dictation | 24 passed; 1 native integration test skipped |
| Diagnostic-enabled build test | 1 passed; default-off behavior covered by Full suite |
| Python icon/App generators, export and APK guards | 31 passed |
| Rust server and load generator | 35 + 1 passed; 3 PostgreSQL tests require hosted CI |
| Rust formatting and Clippy | Passed, warnings denied |
| Canonical catalog and diagnostics mirrors | Current |
| Real Chromium App/icon pages and download guards | Passed |

## Measured line coverage

LCOV counts unique instrumented source lines with positive execution hits. These figures do not claim complete branch coverage, every possible behavior, or physical third-party shortcut correctness. No files were excluded from these totals; uninstrumented native code is outside their denominator.

| Project | Covered / instrumented lines | Coverage |
| --- | ---: | ---: |
| Full | 10263 / 12507 | 82.06% |
| Desktop | 3379 / 4592 | 73.58% |
| Lite | 1775 / 1933 | 91.83% |

Selected boundaries: Full PNG validation and received-profile icon validation 100%; icon download/cache 98.89%; Regular Home 94.00%; Desktop App bundle decoder 100%; Lite strict App library model 100%. Remaining UI, OS/native adapters and error branches mean the whole product is not 100% line-covered.

Raw local LCOV files are `coverage/lcov.info`, `desktop_companion/coverage/lcov.info` and `apps/bluetooth/coverage/lcov.info`. Logs and the per-module summary are under ignored `build/icon-shortcut-audit/`. CI now uploads Full/Desktop and Lite LCOV artifacts and runs the diagnostic-enabled test and browser damage cases on future changes.

## Build and physical acceptance

The previous source passed Android/Windows builds, but Linux dependency installation timed out and Apple jobs were cancelled. This revision must receive fresh cross-platform build results before main integration; results are recorded separately below when available.

Automated tests use mock native input or loopback HTTP. The second Mac's persistent mouse failure is still a physical acceptance item: check the running App's Accessibility permissions and follow `2026-11-18-host-switch-pointer-and-sidebar.md`. The reproduced stale shortcut race and touchpad lifecycle fixes do not prove that distinct permission/native-input issue resolved. No claims are made that all 501 third-party chords were exercised on installed Mac/Windows/Linux Apps. No public platform deployment was performed.

Another user task is updating Android launcher artwork. Those working files are preserved and excluded from this change; canonical App library artwork was not modified.
