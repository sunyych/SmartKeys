# Shortcut usage, community and backup validation

Validation date: 2026-10-21. Development used the requested Luna coders with
parent review of storage, upload consent, API compatibility and restoration.

## Flutter and Dart

All four package analyzers passed without issues. Full suites passed as follows:

| Package | Passed | Skipped |
| --- | ---: | ---: |
| Mobile app | 171 | 0 |
| Desktop companion | 30 | 0 |
| Shared protocol | 6 | 0 |
| Local dictation | 24 | 1 |
| Total | 231 | 1 |

The skipped existing SenseVoice FFI regression requires local model, Chinese/
English audio and native-library fixtures that were not configured for this run.
No speech recognition quality or physical-device result is claimed from these
tests. The Dashboard phone/tablet and unconfigured Google-backup screenshots
were generated and visually checked. The focused settings/Dashboard suite also
passed 25 tests without missed-tap warnings.

Measured Dart LCOV line coverage (covered/instrumented lines):

| Package | Lines | Coverage |
| --- | ---: | ---: |
| Mobile app | 5,689 / 7,405 | 76.83% |
| Desktop companion | 1,158 / 1,844 | 62.80% |
| Shared protocol | 304 / 351 | 86.61% |
| Local dictation | 468 / 706 | 66.29% |
| Merged | 7,619 / 10,306 | 73.93% |

These percentages describe the measured Dart LCOV records, not Rust or native
platform coverage. Generated outputs are `coverage/summary.json`,
`coverage/local-dictation-merged.lcov` and the 72-entry screenshot gallery at
`build/ui_screenshots-usage/index.html`.

Android debug APK compilation passed, including the Google native plugin.
The 16 Kotlin unit tests passed with zero failures or skips. The inherited
`JAVA_HOME` referenced an absent JDK; the Kotlin task was rerun with the same
Android Studio JBR used by Flutter, and the original script's gallery/coverage
finalization stage was then resumed. Current dependency/Kotlin deprecation
warnings remain; they did not fail compilation with the installed toolchain.

The APK is `build/app/outputs/flutter-apk/app-debug.apk` (248,080,281 bytes), SHA-256
`8706e717f3e3140a5ffffc0bdea141b98a2e144ac8006d273c66318e53fde357`.
No public API URL or Google client IDs are embedded in this validation build.

```powershell
./scripts/validate_local_dictation.ps1 -BuildAndroid
```

## Rust and deployment

`cargo fmt --check`, strict all-target Clippy and all-target tests passed.
The test run contains 17 server tests and one load-generator collector test,
with zero failures or ignored tests. The PostgreSQL HTTP suite ran against a
disposable PostgreSQL 17 instance using isolated schemas. It covers concurrent
idempotent submissions, conflicts, withdrawal, publication thresholds, periods,
optional profession filters, signed Google-token validation and account isolation.
Profile validation tests also cover keyboard aliases, mouse coordinates and
preservation of custom Desktop action JSON without executing it.

```powershell
cargo fmt --manifest-path community_server/Cargo.toml --check
cargo clippy --manifest-path community_server/Cargo.toml --locked --all-targets -- -D warnings
# Set TEST_DATABASE_URL to a disposable PostgreSQL database first.
cargo test --manifest-path community_server/Cargo.toml --locked --all-targets -- --include-ignored
```

The final Linux deployment image built successfully with Rust 1.98.1:
`sha256:fa3ac32496df111c3b03b36a418ffb0b60fe626c113f860b89aaafc26d4d22e1`.
Its health and profession-filtered ranking endpoints were checked while running
as UID/GID 10001, with a read-only filesystem and all capabilities dropped.
Compose configuration and the Caddy HTTPS configuration passed validation.
No public host was deployed or TLS certificate requested during these checks.

The production Dart community client also passed the live loopback contract
script against Rust and PostgreSQL. It submitted three `design`-tagged batches,
checked global and profession rankings, retried without double-counting, checked
repeat withdrawal, and withdrew all its test batches.

```powershell
$env:SMARTKEYS_TEST_SERVER_URL = 'http://127.0.0.1:18443'
dart run scripts/verify_community_client_test.dart
```

## Measured local performance

The test used an Intel Core i7-11700 (8 cores/16 threads), a native Windows Rust
release server, PostgreSQL 17 in Docker, and loopback HTTP without TLS. The
published ranking was populated with all 15 categories before measurement.
PostgreSQL durability defaults were retained. Concurrency was 32, with 2,000
GET requests and 2,000 contribution/withdrawal pairs.

| Operation | Samples | Errors | p50 | p95 |
| --- | ---: | ---: | ---: | ---: |
| Ranking GET | 2,000 | 0 | 12.72 ms | 26.47 ms |
| Contribution POST | 2,000 | 0 | 81.22 ms | 196.19 ms |
| Withdrawal DELETE | 2,000 | 0 | 81.99 ms | 196.95 ms |

Ranking throughput was 2,252.2 requests/s. Combined POST plus DELETE throughput
was 335.9 HTTP operations/s; this is not 335.9 uploaded batches/s. These are
local measurements, not a production capacity guarantee or a claim of peak
performance. The reproduction command is documented in the service README.
The generator consumes every response, counts failed requests, exits nonzero
on failures, and uses unique batches that it withdraws after submission.

Contribution writes and withdrawals use PostgreSQL functions to complete each
transaction in one application/database round trip. Lifetime click totals are
cached locally, while the mobile journal appends events without rewriting its
entire history for every click.

## Acceptance boundaries

The user has not supplied Google OAuth client IDs or a deployment hostname.
Google sign-in and public internet deployment therefore remain configuration
and operational acceptance steps. Authentication tests use signed local JWKS
fixtures; they do not claim a real Google account login. See
[Google setup](GOOGLE_BACKUP.md) and [service deployment](../community_server/README.md).

Widget screenshots show simulated phone/tablet sizes. They do not establish
physical-device or iOS native acceptance. The desktop Dart checks do not build
the Windows native application. On this machine the workspace volume does not
support Flutter's generated Windows plugin symlinks; for the full validation
script the desktop Windows platform directory is temporarily moved inside the
ignored build directory and always restored in `finally`.

Detailed click events and timestamps remain local. Public contributions contain
only allowlisted category counts and an optional self-selected profession tag.
Google backup uses a separate authenticated API and never includes usage history,
anonymous deletion receipts or device-pairing credentials.
