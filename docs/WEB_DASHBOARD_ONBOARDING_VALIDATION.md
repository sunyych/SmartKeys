# Web Dashboard and optional mobile setup validation

Validation date: 2026-10-21. Luna coders implemented the mobile setup, client/UI
and Rust service in separate file scopes; the parent reviewed and integrated
the work, checked the browser and managed Docker/Git delivery.

## Behavior and data boundaries

- First launch offers optional profession and computer proficiency choices.
  Saving or skipping does not enable sharing or upload data. Settings can reopen
  setup; each contribution preview can change or omit either saved default.
- Setup preferences remain in the private, backup-excluded mobile directory.
  They are absent from Google backups/Profile exports and survive clearing click
  history. Concurrent repository operations are serialized across instances.
  Storage errors allow Home and cannot overwrite existing choices after a
  failed Settings load.
- The public API accepts optional allowlisted experience metadata, supports
  combined profession/experience filters and retains legacy payload hashes and
  the original SQL submission entry point. Migration 002 preserves existing
  batches, aggregates, receipts and account backups.
- Rust embeds the Chinese browser Dashboard and its local CSS/JavaScript.
  Published totals, proportional bars and the table support all/7d/30d plus
  combined filters. Categories need three batches in the selected scope;
  batches do not represent verified unique people.

## Flutter, Dart and Android

All four analyzers passed. The complete validation script passed with Android
build and Kotlin checks:

```powershell
./scripts/validate_local_dictation.ps1 -BuildAndroid
```

| Package | Passed | Skipped | Covered / instrumented Dart lines | Coverage |
| --- | ---: | ---: | ---: | ---: |
| Mobile app | 186 | 0 | 5,914 / 7,640 | 77.41% |
| Desktop companion | 30 | 0 | 1,158 / 1,844 | 62.80% |
| Shared protocol | 6 | 0 | 304 / 351 | 86.61% |
| Local dictation | 24 | 1 | 468 / 706 | 66.29% |
| Total | 246 | 1 | 7,844 / 10,541 | 74.41% |

The existing SenseVoice FFI regression remains skipped because its local model,
audio and native-library fixtures are not configured. No physical-device speech
quality or native Windows build acceptance is claimed. The D: filesystem cannot
create Flutter desktop plugin links, so the desktop Windows platform directory
was temporarily moved inside build/ during package validation and restored in
finally; desktop Dart analysis/tests ran normally. Android Studio JBR and
repository-owned TEMP/TMP/PUB_CACHE were used. Existing SDK Zone.Identifier and
dependency/Kotlin deprecation warnings did not fail validation.

Android debug APK compilation passed; the 16 Kotlin tests have zero failures,
errors or skips. APK: `build/app/outputs/flutter-apk/app-debug.apk`,
272,530,051 bytes, SHA-256
`c2ae300b1342bf17d135e8c9756de2d4eaac0a4ed3837eff3d72dcc0400b74de`.
The validation build contains no public service URL or Google OAuth IDs.

The 74-entry screenshot gallery is at
`build/ui_screenshots-web-setup/index.html`. The onboarding phone view and
Dashboard experience filters were visually reviewed. A final focused run checks
the last preview wording and screenshot theme changes separately from full-suite
coverage: mobile analysis and all 27 focused tests passed. Coverage above comes
from the full validation run.

## Rust, PostgreSQL and browser

`cargo fmt --check`, strict all-target Clippy and all-target tests passed:
20 server tests plus one load-generator test, zero failed or ignored. The
PostgreSQL tests ran against a disposable PostgreSQL 17 instance, including
001-only seeded data migrated twice, old HTTP retry/hash compatibility,
concurrent requests, withdrawal, publication threshold, combined period filters,
Google token verification and backup isolation.

The real Dart client contract ran against the isolated Linux Docker API and
verified profession/experience intersections, duplicate retries and withdrawal
back to the original ranking baseline. All test batches were withdrawn.

Headless Microsoft Edge with a fresh isolated browser context verified desktop
1440x1050 and mobile 390x844 layouts, combined filters, 7d/30d, hidden
below-threshold categories, totals/order, empty state, HTTP 429, network failure,
no JavaScript exceptions and no page width overflow. It also checked that
90:30 counts render as 100px:33px bars with visible numeric labels. Screenshots
are under `build/community-runtime/web-qa/`. CUA initialization timed out twice;
browser QA used the bundled Playwright runtime and installed Edge instead.
Synthetic data was confined to the disposable test database.
The final deployed JavaScript also passed browser checks for non-JSON 503/429,
invalid JSON, null or mismatched responses, network failure and recovery to the
real empty ranking. These failures show fixed Chinese messages rather than raw
browser/parser errors, and stale response checks remain after JSON parsing.

## Local Docker runtime

The running service is available at `http://127.0.0.1:18443/`; `/dashboard`
serves the same page. Only the API container was replaced. The existing
`smartkeys-community-db-1` container and
`smartkeys-community_postgres_data` volume were preserved. A private pg_dump
snapshot was saved under ignored `build/community-runtime/backups/` before the
migration. Batch count, backup count and aggregate count matched before/after
the upgrade. Health, embedded page and combined filter responses passed.

Final Linux image:
`sha256:7e60aee931067449a4bf2adba103bfec85d45cc07b61779615691958ff64ba9c`.
The API remains bound to host loopback with proxy trust off, runs as UID 10001
with a read-only filesystem and restarts unless stopped. PostgreSQL has no host
port. Runtime passwords, .env, backups and test artifacts remain ignored.

This local address is for this computer. A mobile production build needs a
reachable HTTPS endpoint; Google account backup additionally needs the OAuth
configuration in [GOOGLE_BACKUP.md](GOOGLE_BACKUP.md). Real Google sign-in and
physical iOS/Android acceptance are not claimed without that setup/devices.

## Remote validation

Both implementation commits were pushed and their remote refs verified:

- `dd09efb66ec70315f337174f42ed7f090bf8b51b`: mobile setup, optional metadata,
  PostgreSQL migration and embedded Dashboard.
- `e39b12ed98ff5b14183f6afccb765f26323a7b84`: final browser error handling and
  corresponding validation evidence; mobile sources are unchanged from dd09efb.

New CI checks completed successfully:

- [Rust/PostgreSQL for dd09efb](https://github.com/sunyych/SmartKeys/actions/runs/39650473399).
- [Rust/PostgreSQL for final web code e39b12e](https://github.com/sunyych/SmartKeys/actions/runs/39651673148).
- [Unsigned iOS build for the mobile changes dd09efb](https://github.com/sunyych/SmartKeys/actions/runs/39650473169).

Unsigned iOS compilation verifies source/plugin linkage only, not signing,
physical-device behavior or Google account login. The delivery evidence update
after these runs changes documentation only.
