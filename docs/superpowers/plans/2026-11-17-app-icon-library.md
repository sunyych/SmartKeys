# App Icon Library and Error Diagnostics Implementation Plan

> **For agentic workers:** Use the user's requested Luna subagents for implementation. The primary agent reviews each deliverable, runs integration verification and owns Git/merge actions.

**Goal:** Finish the new icon-library/diagnostics handoff, preserve the completed editions and QR pairing, and merge the verified result into main.

**Architecture:** One authoritative icon catalog generates offline resources for three Flutter projects and registered Rust downloads. A zero-dependency diagnostics core is shared with a self-contained Lite vendor copy; Full alone owns explicit consent and central uploads. The Rust service validates and bounds anonymous error records separately from usage/account data.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12.2, Android Kotlin, Rust/Axum/PostgreSQL, existing dashboard and artifact-only Actions.

**Spec:** `docs/superpowers/specs/2026-11-17-app-icon-library-design.md`; the three documents and JSON under `docs/handoffs/app-icon-library`.

## Global constraints

- Full/Desktop `1.6.0+8`; independent Bluetooth Lite `1.1.0+2`.
- Keep twelve landscape controls, Desktop-owned assignments, activation/session safeguards and new QR pairing.
- Exactly fifty genuine unique built-ins; ten real web-only additions, never aliases/placeholders counted as resources.
- No expansion of the remote application/shortcut command allowlist from an icon ID.
- Lite has local diagnostics/offline icons only; no Internet/microphone/account/ASR/uploader or parent-source dependency.
- Capture only fixed error codes; no input, key, shortcut, app target, raw exception/stack, token, path, URL query, account/device ID or successful-operation history.
- Fresh explicit Full consent; no reuse of community/usage consent, no historical backfill, immediate cancellation on revoke.
- Local defaults thirty days; user seven/thirty-day choice; hard 1000-event/5-MiB bounds.
- Wire schema 1; twenty events/16 KiB; full Android/iOS only; backend thirty days/100000 bounded rows.
- All writes stay within assigned ownership. No concurrent Flutter runners in the same project. No individual screenshot review.
- User now explicitly authorizes merging to main. Do not create tags, Releases, repositories or deployments.

## Task 1: Integrate verified baselines

**Owner:** Primary agent.
**Files:** Existing merge of origin main QR changes into `feature/app-icon-library`; imported prior validated editions branch.

- [x] Fetch and read `b236431` handoff; retain verified `b50134f` integration instead of resurrecting unfinished WIP `08993e6`.
- [x] Merge current main `b6011ea` QR changes without reverting `1.5.0+7`, landscape or independent Lite.
- [ ] Initialize dependencies; preserve QR scanner/keyboard-covered pairing and Desktop QR regression tests.
- [ ] Commit the integration and this approved-handoff implementation plan before feature development.

## Task 2: Registered assets, generated mapping and existing web library

**Owner:** Luna.
**Files:** `packages/app_icon_catalog/**`, `scripts/generate_app_icon_catalog.py`, four `assets/app_icons` trees, three generated `lib/icons/builtin_icon_catalog.g.dart` files, `desktop_companion/lib/desktop_application_artwork.dart`, icon-specific Rust/web/browser tests and `docs/APP_ICON_SOURCES.md`.
**Consumes:** Required fifty IDs, existing native-icon contracts, bounded PNG policy.
**Produces:** `BuiltinIconEntry`, `builtinIconCatalog`, `builtinIconById`, `canonicalBuiltinIconId`; rich compatible schema-1 `/v1/icons/catalog`; fixed-origin PNG downloads.

- [ ] Add source/hash/date/terms records for each real resource; identify native Explorer and renamed Microsoft Office identity accurately.
- [ ] Prepare and decode sixty 256×256 RGBA contain images, fifty built-in/ten server-only, with distinct hashes and at most 64 KiB each.
- [ ] Implement generator/check mode from canonical JSON; synchronize only fifty built-ins to each app and all sixty to the self-contained server context.
- [ ] Retain native artwork priority and identity keys in Desktop; preserve explicit legacy protocol adaptation without confusing it with a real product.
- [ ] Extend existing web search/deep-link/copy/preview/download/source/terms UI with built-in/online status and bounded loading/error recovery.
- [ ] Test real byte content/MIME/hash, aliases, unknown IDs, ETag/version changes, registered extras, 390px overflow and keyboard navigation.
- [ ] Save current browser screenshots and report generated-file/asset checks to the primary agent.

Verification includes generator check, decoded dimensions/alpha bounds/hash uniqueness, existing Rust icon tests and `community_server/tests/browser_icons.cjs` with a real preview server. No App rebuild is required to demonstrate a newly registered server-only ID.

## Task 3: Pure diagnostics model, strict server endpoint and local-only Lite

**Owner:** Luna platform.
**Files:** `packages/diagnostics_core/**`, `apps/bluetooth/packages/diagnostics_core/**`, synchronization checker, Lite source/UI/tests/pubspec/native version metadata/isolation scripts, `community_server/src/diagnostics.rs`, main router/AppState integration, migration and diagnostics tests.
**Consumes:** Fixed twenty-code registry and exact wire schema in the design.
**Produces:** `DiagnosticCode`, `DiagnosticMetadata`, `DiagnosticEvent`, `ErrorJournal.capture`; local/upload serialization; Lite-local store/UI; `POST /v1/diagnostics/errors`.

- [ ] Write core tests before implementation: strict restoration, hostile extra fields, metadata validation, five-minute de-duplication, separate consent epochs, retention/capacity and snapshot acknowledgement preserving newer occurrences.
- [ ] Implement a core with no I/O/network imports; copy only production code/metadata into Lite and check byte equality.
- [ ] Add local Lite persistence and seven/thirty-day settings, empty/list/details/clear UI, fixed failure instrumentation and actual native app-version retrieval.
- [ ] Consume generated fifty-icon catalog in a local-only searchable Lite gallery; do not add launchers, uploads or online dependencies.
- [ ] Update isolation/export checks to allow only the contained zero-dependency core path and reject parent paths/forbidden imports/permissions.
- [ ] Implement strict backend validation and transactional idempotent storage; reject arbitrary fields, Lite uploads, oversized bodies and conflicting event IDs.
- [ ] Exercise PostgreSQL duplicate/count updates, timestamp/rate/capacity/retention boundaries and absence of public diagnostics queries.
- [ ] Run core/Lite/native/server tests, capture all new Lite states, and independently export/build the updated Lite.

Hostile fixtures must include `CTRL+C`, clipboard/transcript text, private paths, bearer tokens and private addresses; none may survive in local or accepted server serialization. A normal keyboard/mouse/media action must leave the diagnostic count unchanged.

## Task 4: Full icon client, error store, consent and UI

**Owner:** Luna interface.
**Files:** `lib/icons/**` excluding generated file, `lib/diagnostics/**`, new icon/log/consent screens, `lib/bootstrap.dart`, `lib/app.dart`, controller/companion/image-store integration, Full/Desktop pubspec versions and matching tests.
**Consumes:** Generated built-in catalog and platform's pure diagnostics package/schema.
**Produces:** Full searchable icon browser, safe dynamic central cache, independent diagnostic consent and bounded uploader.

- [ ] Test fifty offline entries before any HTTP request; test an extra ID absent from the App build, actual download, hash rejection, restart/offline reuse, eviction and damaged-cache fallback.
- [ ] Keep central resources scoped to configured HTTPS origin and separate from native per-computer images; never expand action permissions.
- [ ] Persist sanitized journal plus independent consent/tombstone; enable only after durable new epoch, cancel synchronously on revoke/clear and exclude past epochs.
- [ ] Read actual package version/build; missing metadata cannot enable uploads with fabricated identifiers.
- [ ] Add a separate exact-body uploader with one active request, twenty-event/16-KiB batches and finite backoff. Upload failures do not generate log feedback loops.
- [ ] Replace ambiguous first-start sharing wording with accurate independent error consent; community features remain in Settings and their prior consent is not migrated.
- [ ] Instrument global/UI, connection, activation, delivery, icon and configuration failures only with fixed codes. Do not pass exception objects or event/input context to the journal.
- [ ] Exercise hostile real error objects through failing service/controller paths and inspect both local persistence and real loopback request bodies.
- [ ] Cover undecided/refused/allow/revoke/re-enable/clear, in-flight cancellation, write failure and no endpoint without blocking normal input.
- [ ] Capture icon built-in/search/empty/download/offline/error and consent/log-empty/list/detail/clear/share-failure states under the current screenshot root.

## Task 5: Integration, artifacts and main merge

**Owner:** Primary agent; fixes return to the owning Luna agent.
**Files:** Artifact CI branches/bootstrap, export verification, current validation docs and one screenshot index.

- [ ] Review code/data/permissions and privacy boundaries; verify journal fields against backend and ensure no ordinary input becomes telemetry.
- [ ] Run Full/Desktop/protocol/core/Lite/Rust analysis and suites, including preserved QR tests, real PostgreSQL and actual icon browser interactions.
- [ ] Validate generated assets in actual APKs, release manifests, safe source exports and exported Lite dependency/build independence.
- [ ] Add `feature/app-icon-library` to existing artifact-only checks; initialize both core test dependencies and generated-data checks on clean runners.
- [ ] Build Android and Desktop packages; wait for successful Windows/macOS/iOS/Linux/diagnostics-server checks.
- [ ] Generate one new `build/handoff-1.6.0/screenshots/index.html`, excluding earlier product galleries and without reading each image.
- [ ] Record exact tests, conditional skips, signatures, endpoint configuration and physical-device limits in the new handoff completion report.
- [ ] Commit/push the feature, fetch current main and preserve newer work, merge the fully reviewed feature into main and push main; verify remote equality and clean status.
- [ ] Deliver current artifacts/records. Previously authorized device updates may use local-only diagnostic consent; never grant sharing or submit genuine diagnostics on the user's behalf.
