# Shortcut Usage Implementation Plan

> **For agentic workers:** Use the user-requested Luna coder subagents for the
> three tasks below; the parent arranges work and checks every change.

**Goal:** Private click history and Dashboard with voluntary aggregate sharing
and a deployable community ranking service.

**Architecture:** Extend the existing usage repository with an append journal.
Keep sharing and public ranking separate from shortcut execution and configuration
export. A Rust Axum/Tokio/PostgreSQL API serves opt-in aggregate contributions over HTTPS.

**Tech Stack:** Flutter/Dart, Kotlin/Swift storage channels, Rust Axum/Tokio/SQLx PostgreSQL,
Caddy and Docker Compose.

**Spec:** ../specs/2026-10-21-shortcut-usage-design.md

## Global Constraints

- Default OFF. No background/automatic uploads.
- No stable installation identifier, raw usage keys, labels or precise times in uploads.
- User controls each submission, clear, sort and withdrawal explicitly.
- API contract, allowlist and ownership follow the spec exactly.
- Preserve existing aggregate statistics without invented click timestamps.
- No invented public host or leaderboard; configure SMARTKEYS_RANKING_URL.

## Task 1: Local history and mobile storage — Luna local coder

Files: existing usage repository, AppController and app.dart; new private usage
directory/catalog; Android/iOS method channels; repository/controller tests.

- [x] Add meaningful tests for persistence/restart, legacy migration, event IDs,
  start-inclusive/end-exclusive queries, append recovery, rapid record/clear and
  the public category allowlist. Run those tests to establish missing behavior.
- [x] Implement agreed event API and serialized persistent journal, with
  `record(String key, String label, {String? publicShortcutId})` and
  `recordsForPeriod({DateTime? start, DateTime? end})`.
- [x] Add mobile backup-excluded directory channel and inject production storage
  without changing test harness memory repositories.
- [x] Record safe categories at local input entry points while preserving click
  attempt semantics and avoiding release double-counting.
- [x] Run targeted repository/controller tests and analysis, inspect failures.

## Task 2: Dashboard and voluntary client — Luna UI coder

Files: SettingsScreen; new Dashboard, sharing repository and HTTP client; tests.

- [x] Test date/sort/clear/navigation states, default-off network behavior,
  serialization excluding local fields, persistent idempotent retry, pending
  submissions during opt-out/clear, and safe withdrawal retry.
- [x] Build Dashboard with local summary/ranking/history, custom dates, explicit
  stable Smart sort and clear confirmation at the bottom.
- [x] Implement preview then submit of only unsubmitted eligible event IDs;
  persist pending batch/receipt before POST and only acknowledge verified success.
- [x] Implement bounded HTTPS client, ranking retrieval and contribution withdrawal.
  Show no-endpoint/empty/offline states clearly. Read public rankings without opt-in.
- [x] Add optional profession tags to per-batch preview and independent public
  ranking filters, preserving tagless defaults and retry identity.
- [x] Run focused widget/client tests; generate Dashboard phone/tablet screenshots.

## Task 3: Deployable API — Luna server coder

Files: community_server/src/**, Cargo.toml/Cargo.lock, tests, Dockerfile, compose.yaml, Caddyfile,
deployment README and environment example.

- [x] Test strict validation, atomic duplicate/conflicting batch IDs, ranking
  threshold/order/periods, deletion authorization/tombstones, payload bounds,
  concurrent duplicates and rate limits via real HTTP requests and concurrent tasks.
- [x] Implement v1 POST/GET/DELETE and health endpoint exactly as specified;
  use PostgreSQL transactions, indexes and an asynchronous connection pool.
- [x] Maintain global and per-profession aggregates with optional fixed tags,
  matching idempotency and withdrawal behavior without Google identity linkage.
- [x] Package the optimized nonroot Rust binary behind Caddy, keep backend port private, persist PostgreSQL
  volume, disable access logging, document TLS/endpoint and anonymity limits.
- [x] Run `cargo test --manifest-path community_server/Cargo.toml` and verify
  container configuration where Docker is available.

## Task 4: Selective Google account backup — Luna local coder + server coder

- [x] Follow the extended design's exact Google/backup API and per-account schema.
- [x] Add google_sign_in, configuration-aware sign-in/sign-out service, bounded
  authenticated HTTPS backup client and independent selective backup screen.
- [x] Offer settings, individual Profiles and custom-image checkboxes; preview
  before manual backup, restore and online backup deletion.
- [x] Add strict serializer/image validation, preserve local data and runtime
  pairing, and atomic controller restore with four-slot preflight checks.
- [x] Add server JWKS verification and account-isolated latest-backup API with
  strict request schema, 20 MiB limit and Postgres migration.
- [x] Test fake signed JWKS/auth rejects and two-account isolation; client payload
  selection/exclusions, unsafe images and failed save preserving local state.
- [x] Document OAuth setup and build variables; do not claim live sign-in without
  the user's missing OAuth project/client configuration.

## Parent review and delivery (all tasks)

- [x] Inspect all diffs for privacy, data-loss and cross-component API issues.
- [x] Run real local client/server integration including duplicate POST and DELETE; measure concurrent upload and ranking throughput with p50/p95 latency.
- [x] Run complete existing validation script with coverage and Android build.
- [x] Inspect responsive Dashboard screenshots and record actual evidence/limits.
- [x] Update feature/validation documentation, stage only requested changes,
  commit and push main, verify remote SHA and clean working tree.
