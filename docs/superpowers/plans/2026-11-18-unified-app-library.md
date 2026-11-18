# Unified App Library Implementation Plan

> **For agentic workers:** Execute task-by-task with the user-authorized Luna development agents; root coordinates review, integration, builds and delivery.

**Goal:** Bind each App's icon to its supported OS shortcut libraries across Desktop, Full, Lite and the online catalog.

**Architecture:** A canonical App registry and generated strict Dart model feed all clients. Desktop and offline Lite install associated profiles through existing persistence paths; the online service publishes validated immutable App bundles and a web catalog.

**Tech Stack:** Flutter/Dart, Python generation, Rust/Axum, JavaScript browser frontend, Android/Kotlin.

**Spec:** `docs/superpowers/specs/2026-11-18-unified-app-library-design.md`

## Global constraints

- Twelve-key landscape UI; preserve custom profiles and private startup chords.
- macos/windowsLinux families with separate explicit supportedOS.
- No arbitrary executable actions in public bundles; unassigned actions send no input.
- Lite is offline Bluetooth only, independently buildable.
- Retain legacy icon routes, provenance and aliases; do not merge Codex and ChatGPT App identities.
- Full/Desktop 1.8.0+10; Lite 1.3.0+4. No public deployment without a target.

## Task 1 — Canonical data and offline Lite (Luna)

Files: `packages/app_library/*`, `scripts/generate_app_library.py`, generated model paths in the spec, `apps/bluetooth/lib/{local_profiles,lite_controller,local_settings,lite_editors}.dart`, related tests.

Produces the specified shared catalog/model interface and registry for all existing icon Apps. Coordinates DTO shape with both consumer agents before generation. Add public-schema rejection and OS-availability tests, then implement source-verified bindings/unassigned actions. Add explicit Lite target OS and atomic local profile install with source metadata. Test persistence failure rollback, unassigned no-input, legacy profile preservation and no launch-binding mutation. Run generator check, Lite analysis/tests and relevant Python tests. Do not commit while other agents are editing; root commits the reviewed stage.

- [x] Freeze DTO/schema with consumers and generate shared data.
- [x] Curate App support/provenance and strict validation tests.
- [x] Implement offline Lite installation and configuration UI.
- [x] Run targeted validation and send review evidence.

## Task 2 — Desktop and Full (Luna Interface)

Files: `desktop_companion/lib/{desktop_controller,desktop_app}.dart`, Desktop library UI, `packages/lumiakeys_protocol/lib/lumiakeys_protocol.dart`, `lib/icons/app_icon_library_screen.dart`, relevant controller/protocol/UI tests.

Consumes Task 1 generated App model; produces Desktop atomic installation and synced source-identified profiles, Full catalog preview and usable manual profile navigation. Extend RemoteProfile only with optional metadata. Preserve managed foreground protection and installed launch-only handling. Test actual-host OS, unsupported variant rejection, add-copy/explicit replacement, persistence rollback, protocol migration, manifest/profile selection and existing launch safety. Run affected suites and analysis.

- [x] Agree DTO with Luna; implement source metadata and install transaction tests.
- [x] Implement Desktop catalog and profile flow.
- [x] Update Full preview and received-profile navigation.
- [x] Run focused regression suites and report.

## Task 3 — Online App platform (Luna Platform)

Files: `community_server/src/app_library.rs`, routes/assets and `community_server/src/web/*`, server/browser tests and docs. Consumes the canonical registry and icon assets; does not mutate Task 1-owned generator files without coordination.

Produce bounded catalog/App-bundle endpoints with hash verification and browser search/OS/action previews/downloads. Retain icon compatibility. Test malformed payloads, impossible OS/family pairs, forbidden actions, unsupported methods, immutable hashes and actual browser downloads. Run Rust and frontend checks; local acceptance only until a deployment target is available.

- [x] Agree JSON shape and route contract with Luna.
- [x] Implement strict public validation and immutable bundle routes.
- [x] Implement unified App web catalog.
- [x] Run service/browser tests and report.

## Task 4 — Integration and delivery (root)

- [x] Review diffs, official shortcut provenance, cross-component compatibility and destructive/persistence boundaries.
- [x] Bump versions; update release verifiers for new App-library markers and handoff documentation.
- [x] Run full affected tests/analysis, generation checks and fresh NTFS release builds.
- [x] Verify packaged runtime/hashes/signing; install Android/Windows upgrades preserving data.
- [x] Commit/push feature, check CI, merge passing work into main and push.
- [ ] Deliver packages and concise acceptance report, distinguishing public deployment from local validation.
