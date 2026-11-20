# SmartKeys community ranking service

This directory contains the Rust API and a PostgreSQL-backed Docker deployment. The public contribution tables store category counts, one-way deletion-token and payload hashes, random batch IDs, server receipt time, and withdrawal state; they contain no raw shortcut events, click timestamps, device IDs, Google subjects, or IP addresses. The separate account-backup table stores the Google subject verified from the ID token, the selected settings/Profile/image snapshot, and its update time. The network connection still exposes a transport IP to the hosting provider; public submissions do not establish verified unique users and rankings are not fraud-proof.

## API

- `POST /v1/contributions`: strict JSON schema, exact fields, lowercase 32-hex batch ID, lowercase 64-hex deletion token, one to fifteen unique allowlisted category IDs, positive integer counts, total at most 100,000 and body at most 16,384 bytes. New batches return 201, identical retries return 200, conflicts return 409 and withdrawn replay returns 410.
- `POST /v1/contributions` accepts an optional JSON `tag` of `software_engineering`, `design`, `video_editing`, `office`, or `other`; missing or `null` means global only. Tagged submissions also count in the global ranking. The tag is self-selected and is not linked to Google accounts or inferred.
- `POST /v1/contributions` also accepts optional `experience` of `beginner`, `intermediate`, or `advanced`. `null` and omission mean no experience selection. It is included in the idempotency hash only when supplied, preserving retries queued by older app versions.
- `GET /v1/rankings?period=all|7d|30d[&tag=<id>][&experience=<id>]`: tag and experience filters can be combined and select their intersection; omitted filters select the corresponding unfiltered scope. `tag=null` or `experience=null` as query strings are invalid. The endpoint uses server receipt time, publishes a category after three separate batches in the selected scope, and sorts count descending then category ID ascending. The 7d and 30d periods use the latest 7 or 30 UTC calendar days. The response echoes `tag` and `experience` as null or the selected IDs. `contributions` means submitted batches, not users.
- `GET /` and `/dashboard`: embedded Chinese-language dashboard with local CSS/JavaScript, period/profession/experience filters, published-only summaries, and table/chart views. Assets are served same-origin with CSP and cache headers; the page exposes no account backup or private batch records.
- `DELETE /v1/contributions/{batch_id}`: requires `Authorization: Bearer <delete_token>`, returns 204 for a valid first or repeated withdrawal, and removes category counts while retaining a minimal tombstone.
- `GET /healthz`: returns a data-free health response.
- `PUT /v1/account/backup`: requires a verified Google ID token and atomically replaces the caller's selected settings/Profile/image snapshot. Companion action values are retained only as nonempty JSON objects up to 16 KiB UTF-8, with `keyCode: null` and empty modifiers; the server does not execute them.
- `GET /v1/account/backup`: returns the authenticated account's latest snapshot, or 404 when none exists.
- `DELETE /v1/account/backup`: deletes the authenticated account's snapshot; repeat deletion returns 204.

Errors have short fixed codes. API requests and responses are not access-logged. Rate limiting is bounded in memory and configurable with `RATE_LIMIT_PER_MINUTE` (default 120) and `RATE_LIMIT_MAX_CLIENTS` (default 10,000).

## Deploy

1. Point a DNS name you control at the deployment host and allow inbound TCP 80/443 (and UDP 443 if desired for HTTP/3). The service does not include a public hostname.
2. Copy `.env.example` to `.env`, set `PUBLIC_DOMAIN` to that real DNS name, and generate a long URL-safe random `POSTGRES_PASSWORD`. Keep `.env` private and outside source control.
3. The authenticated backup API remains available for existing deployments and legacy clients. Keep their configured `GOOGLE_CLIENT_IDS` and PostgreSQL data if they still serve saved backups. Leave the variable empty on ranking-only deployments. The backup endpoints return 503 without it. The server verifies Google ID tokens against Google's fixed official JWKS endpoint with RS256, issuer, audience, expiry and subject checks.
4. From this directory, run `docker compose up -d --build`. Caddy obtains and renews TLS certificates for the configured domain. PostgreSQL has a persistent Docker volume and is not published to the host. The API has no published host port, runs as UID 10001, waits for PostgreSQL health, and is reachable through the private Compose network.
5. Back up the PostgreSQL volume using a PostgreSQL-aware backup procedure and protect the backup. Restoring the database restores batch tombstones, accepted aggregates and account snapshots.
6. Build the app with its compile-time `SMARTKEYS_RANKING_URL` set to the real HTTPS origin. The current mobile app uses the ranking and contribution APIs. For historical backup behavior, see [legacy Google account backups](../docs/GOOGLE_BACKUP.md).

The proxy is the only route to the API in this Compose setup. `TRUST_PROXY=1` therefore accepts Caddy's forwarded client IP for transient rate limiting. Keep port 8080 private if changing the network; never expose it directly while proxy trust is enabled. Caddy and the application have request access logs disabled.

## Local development and checks

Install Rust 1.98 or newer and a PostgreSQL instance. Set `DATABASE_URL` to a database the server may use, then run `cargo run --manifest-path Cargo.toml` from this directory. The server applies idempotent migrations 001, 002 and 003 at startup; migration 002 adds experience aggregates while retaining the legacy SQL entry point and existing data. The server listens on `0.0.0.0:8080` by default; override `LISTEN_ADDR` as needed.

Run unit tests with `cargo test --locked --all-targets`. The real HTTP integration tests use a disposable PostgreSQL database and create uniquely named temporary schemas. Set `TEST_DATABASE_URL` to a test database and run `cargo test --locked --all-targets -- --include-ignored`. They check concurrent idempotency, conflict, withdrawal and replay, legacy-data migration/retry, combined tag/experience period filters, ranking threshold/order, dashboard routes and headers, and signed Google-token backup isolation. Do not reuse a production database for tests.

For a loopback-only async load run against an isolated server instance, set `RATE_LIMIT_PER_MINUTE=1000000` and `RATE_LIMIT_MAX_CLIENTS=100000`, then run `cargo run --release --example loadgen -- http://127.0.0.1:8080 32 2000`. The generator refuses non-loopback URLs, measures ranking GET and unique POST plus receipt DELETE latency, and reports throughput and p50/p95. Use only a disposable database because it writes and deletes test batches.

This is account-free aggregate sharing, not anonymous transport. A lost app receipt cannot be recovered through an account, and the operator cannot establish that separate batches represent separate people.


## Optional error diagnostics

Full mobile diagnostics use an independent explicit consent and the compile-time `SMARTKEYS_DIAGNOSTICS_URL`. This value must be the complete HTTPS endpoint, for example `https://<your-controlled-domain>/v1/diagnostics/errors`, not just an origin. No default center is invented or deployed by this code. Lite has local logs only and never uploads.

`POST /v1/diagnostics/errors` accepts schema 1, at most 20 fixed-code events and 16 KiB. Unknown fields, raw messages/stacks/input, identities, Lite editions, invalid versions/UUIDs/timestamps and arbitrary codes are rejected. Responses contain accepted random event IDs or fixed error codes. There is no diagnostics read/list/dashboard route. Network infrastructure still sees requests; transport is not promised to be anonymous.

Migration 003 creates only bounded fixed metadata/code/count fields. Transactions share a diagnostics-specific advisory lock for conflict checking, idempotent maximum counts and global capacity enforcement. Storage retains at most 100000 events globally and 30 days, with hourly background cleanup and cleanup on each batch. It stores no IP, user/device identifiers, credentials or event content. Existing transient in-memory rate limiting applies.

The diagnostics tests include strict field/body validation, fixed failure responses and loopback HTTP. `cargo test --locked diagnostics::tests -- --include-ignored` additionally requires the disposable `TEST_DATABASE_URL`; it checks repeat-count updates, conflicting IDs, concurrent capacity and retention in its own temporary schema. No real user diagnostics should be submitted for testing.


## Registered App and shortcut libraries

`GET /apps` is the unified App catalog: an App card combines its registered icon,
explicit computer operating systems, keyboard-library previews, shortcut sources,
brand terms and a JSON bundle download. `/icons` and every `/v1/icons/` route
remain compatible. A `windowsLinux` keyboard family does not imply that an App
supports Linux; each library lists its actual `supportedOS`. Native, web and
terminal contexts are explicitly identified. Unassigned actions have no keys and
require configuration; the server does not infer Ctrl/Command replacements.

- `GET /v1/apps/catalog` returns the strict public schema 1 registry with at most
  256 Apps, 512 KiB, a catalog version and conditional ETag responses.
- `GET /v1/apps/{canonicalAppId}/bundle` returns the current reviewed bundle with
  `Cache-Control: no-cache`. Its exact envelope is `schemaVersion: 1`, `app`
  (one registry record), and `icon` (`id`, `sha256`, `pngBase64`). The bundle is at
  most 128 KiB; the exact registered PNG is at most 64 KiB, 256 by 256 pixels.
- The bundle ETag is the SHA-256 of the entire JSON byte stream.
  `Content-Location` identifies `/v1/apps/{canonicalAppId}/bundles/{sha256}.json`.
  That immutable route serves those exact bytes with a one-year immutable cache
  policy and supports ETag 304. A removed or superseded publication hash returns
  404 rather than different bytes. Retaining older publications indefinitely is
  outside this static registry's contract.
- Unknown IDs/hashes return 404; POST, PUT and DELETE are not publication routes
  and return 405 on registered GET paths. App IDs are canonical only: the old
  `codex` artwork alias remains available under `/v1/icons/codex`, and never
  becomes a ChatGPT/Codex shortcut-library identity.

Publication is Git-reviewed static data: maintain `packages/app_library/catalog.json`
and the canonical artwork registry, run both generators/checks, review their diff,
then build the server. Generated `assets/app_library/catalog.json` and PNGs stay
inside the Docker context. No SQL migration, submission endpoint, administrator
website or automatic public deployment is introduced. Existing private account
backups, ranking contributions and independent diagnostics consent are unchanged.
Private backup action validation is deliberately not reused for public bundles.

Every public action is one bounded keyboard chord (unique CTRL/ALT/SHIFT/META
modifiers followed by one allowed key) or an explicit unassigned action. Shell,
paths, launch parameters, macros, private installed IDs, voice, KVM and unknown
JSON fields are rejected. App/library/action IDs, source URLs, OS-family pairs,
duplicate identities, references, icon hashes/bytes and package sizes are checked
before a publication can be served. Source/terms URLs are display links only;
the server does not fetch user-supplied resources or execute library contents.

A download is configuration data, not execution or a permission grant. The web
page verifies the same-origin bundle identity, whole-body hash, registered PNG,
OS/action schema and byte limits before offering its download. Clients still
preview and atomically install a compatible library; the Desktop alone checks
whether an application is installed locally. Lite retains only its offline data.

For a local database-free preview, set `LISTEN_ADDR=127.0.0.1:18742` and run
`cargo run --locked -- --apps-preview`, then open `/apps`. The legacy
`--icons-preview` flag also exposes `/apps`. These preview modes are for local
acceptance, not a configured public deployment. No production hostname is
provided by this feature.

Run `cargo test --locked app_library::tests` for strict payload, all-publication
hash/PNG, immutable HTTP and method checks. `tests/browser_apps.cjs` uses
`APP_BASE_URL` (or `ICON_BASE_URL`) and the existing Playwright runner to check real
JSON downloads, OS filtering, previews, unassigned actions, unsafe bundles,
503 recovery and 390-pixel layout. The existing icon browser acceptance remains
in CI alongside it.
