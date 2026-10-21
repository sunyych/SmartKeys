# Web Dashboard and Mobile Setup Implementation Plan

> **For agentic workers:** Use the user-requested Luna coder subagents with
> separate file ownership; the parent reviews interfaces, tests and delivery.

**Goal:** Serve a usable public web Dashboard and let mobile users optionally
choose anonymous profession/proficiency metadata during first-launch setup.

**Architecture:** Embed static assets in Rust, reuse the ranking API and add one
optional experience dimension with PostgreSQL aggregates. A private mobile setup
repository supplies defaults to the existing manual contribution preview.

**Tech Stack:** Rust/Axum/SQLx/PostgreSQL, HTML/CSS/JavaScript, Flutter/Dart, Docker.

**Spec:** ../specs/2026-10-21-web-dashboard-onboarding-design.md

## Global constraints

- No automatic upload or sharing opt-in; all fields optional and allowlisted.
- experience IDs: beginner, intermediate, advanced; existing profession IDs stay.
- Preserve schema_version 1, legacy pending hashes, receipts and persistent data.
- Count publication by batches, never label it verified unique people.
- Keep backend Rust/PostgreSQL, assets local and production connections HTTPS.
- Parent owns SDK/Docker validation scheduling; no concurrent Flutter commands.

## Task 1: Optional first-launch setup — Luna mobile coder

Ownership: new community_setup_repository.dart, setup screen/gate, app.dart,
settings_screen.dart, new setup repository/widget tests. Other App files owned
by Task 2 remain untouched.

- [x] Test default, completion/skip/restart, validation, interrupted persistence,
  failure allowing Home and Settings reopen without any network call.
- [x] Implement the exact repository/preferences interface in the spec under
  privateUsageDirectory, without adding fields to AppConfig/Google backups.
- [x] Build concise optional profession/proficiency setup using current app
  styling, explain manual sharing, persist Finish/Skip and allow reopening.
- [x] Insert the production launch gate; preserve existing controller-injected
  Home fixtures and add dedicated real gate tests.
- [x] Format and hand source to parent for focused and full Flutter validation.

## Task 2: Contribution metadata and mobile Dashboard — Luna client/UI coder

Ownership: shortcut_community_client.dart, shortcut_community_store.dart,
usage_dashboard_screen.dart, their existing tests and live contract script.

- [x] Extend nullable experience API/serialization and validation, preserving
  old constructors, local pending records and no-experience payload behavior.
- [x] Test both filter query parameters and echoed metadata, invalid values,
  no private fields in payload and immutable experience on retry/withdrawal.
- [x] Load setup defaults at preview time, show optional proficiency alongside
  profession, and add independent combined public ranking filters.
- [x] Extend widget tests for saved defaults and per-batch override/omission;
  use bounded real-I/O waits when observing file-backed async state.
- [x] Extend the live loopback contract script to exercise combined filters and
  deduplication/withdrawal; hand source to parent before running SDK tools.

## Task 3: Rust metadata contract and embedded web — Luna server coder

Ownership: community_server/** and service README; update CI only if required.

- [x] Add experience validation and nullable response/query fields; preserve
  the old canonical hash for absent experience and reject conflicting retries.
- [x] Add idempotent incremental schema/functions and derived totals for
  experience plus combined tag/experience queries and atomic withdrawal.
- [x] Test migration from existing data, legacy retry, empty/combined/period
  ranking scopes, publication threshold and concurrent duplicate/delete cases.
- [x] Add embedded page/assets and root/Dashboard routes, correct headers,
  current style, accessible controls/chart/table and stale-response handling.
- [x] Test public asset routes with real HTTP and keep backup/auth APIs intact.
- [x] Run fmt, strict all-target Clippy and disposable-Postgres tests; report
  exact results and keep the live runtime volume untouched.

## Parent review and delivery

- [x] Review contract alignment and privacy; run live Dart-to-Rust combined
  filter contract and browser QA at desktop/mobile sizes with disposable data.
- [x] Run full Flutter/Dart checks/coverage, Android build and Kotlin tests.
- [x] Build the final Linux image; replace only the running API container,
  verify persistent DB mount and browser Dashboard at port 18443.
- [x] Document measured checks and setup behavior; stage only this scope,
  commit/push main, verify remote SHA/clean status and native/server CI.
