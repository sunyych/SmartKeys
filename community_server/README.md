# SmartKeys community ranking service

This directory contains the Rust API and a PostgreSQL-backed Docker deployment. The public contribution tables store category counts, one-way deletion-token and payload hashes, random batch IDs, server receipt time, and withdrawal state; they contain no raw shortcut events, click timestamps, device IDs, Google subjects, or IP addresses. The separate account-backup table stores the Google subject verified from the ID token, the selected settings/Profile/image snapshot, and its update time. The network connection still exposes a transport IP to the hosting provider; public submissions do not establish verified unique users and rankings are not fraud-proof.

## API

- `POST /v1/contributions`: strict JSON schema, exact fields, lowercase 32-hex batch ID, lowercase 64-hex deletion token, one to fifteen unique allowlisted category IDs, positive integer counts, total at most 100,000 and body at most 16,384 bytes. New batches return 201, identical retries return 200, conflicts return 409 and withdrawn replay returns 410.
- `POST /v1/contributions` accepts an optional JSON `tag` of `software_engineering`, `design`, `video_editing`, `office`, or `other`; missing or `null` means global only. Tagged submissions also count in the global ranking. The tag is self-selected and is not linked to Google accounts or inferred.
- `GET /v1/rankings?period=all|7d|30d[&tag=<id>]`: omitting the `tag` query parameter selects the global ranking; passing an allowlisted ID selects that tag. `tag=null` as a query string is not valid. The endpoint uses server receipt time, publishes a category after three separate batches in the selected scope, and sorts count descending then category ID ascending. The 7d and 30d periods use the latest 7 or 30 UTC calendar days. The response echoes `tag` as null or the selected ID. `contributions` means submitted batches, not users.
- `DELETE /v1/contributions/{batch_id}`: requires `Authorization: Bearer <delete_token>`, returns 204 for a valid first or repeated withdrawal, and removes category counts while retaining a minimal tombstone.
- `GET /healthz`: returns a data-free health response.
- `PUT /v1/account/backup`: requires a verified Google ID token and atomically replaces the caller's selected settings/Profile/image snapshot. Companion action values are retained only as nonempty JSON objects up to 16 KiB UTF-8, with `keyCode: null` and empty modifiers; the server does not execute them.
- `GET /v1/account/backup`: returns the authenticated account's latest snapshot, or 404 when none exists.
- `DELETE /v1/account/backup`: deletes the authenticated account's snapshot; repeat deletion returns 204.

Errors have short fixed codes. API requests and responses are not access-logged. Rate limiting is bounded in memory and configurable with `RATE_LIMIT_PER_MINUTE` (default 120) and `RATE_LIMIT_MAX_CLIENTS` (default 10,000).

## Deploy

1. Point a DNS name you control at the deployment host and allow inbound TCP 80/443 (and UDP 443 if desired for HTTP/3). The service does not include a public hostname.
2. Copy `.env.example` to `.env`, set `PUBLIC_DOMAIN` to that real DNS name, and generate a long URL-safe random `POSTGRES_PASSWORD`. Keep `.env` private and outside source control.
3. For account backup, set `GOOGLE_CLIENT_IDS` to the comma-separated Google Web OAuth client IDs accepted by this deployment. Leave it empty until configured; backup endpoints return 503, while community rankings continue to work. Do not add a Google client secret. Google ID tokens are verified against Google's fixed official JWKS endpoint with RS256, issuer, audience, expiry and subject checks. The server stores only the verified subject, selected JSON snapshot and update time.
4. From this directory, run `docker compose up -d --build`. Caddy obtains and renews TLS certificates for the configured domain. PostgreSQL has a persistent Docker volume and is not published to the host. The API has no published host port, runs as UID 10001, waits for PostgreSQL health, and is reachable through the private Compose network.
5. Back up the PostgreSQL volume using a PostgreSQL-aware backup procedure and protect the backup. Restoring the database restores batch tombstones, accepted aggregates and account snapshots.
6. Build the app with its compile-time `SMARTKEYS_RANKING_URL` and `SMARTKEYS_BACKUP_URL` set to `https://<your-domain>`. Set the matching mobile Google Web/iOS client IDs and Android package/signing SHA registrations. iOS also needs the registered reversed-client-ID URL scheme in `Info.plist`. The client requires HTTPS in production; do not point it at the placeholder domain.

The proxy is the only route to the API in this Compose setup. `TRUST_PROXY=1` therefore accepts Caddy's forwarded client IP for transient rate limiting. Keep port 8080 private if changing the network; never expose it directly while proxy trust is enabled. Caddy and the application have request access logs disabled.

## Local development and checks

Install Rust 1.98 or newer and a PostgreSQL instance. Set `DATABASE_URL` to a database the server may use, then run `cargo run --manifest-path Cargo.toml` from this directory. The server applies the idempotent SQL migration at startup and listens on `0.0.0.0:8080` by default; override `LISTEN_ADDR` as needed.

Run unit tests with `cargo test --locked`. The real HTTP integration test uses a disposable PostgreSQL database and creates a uniquely named temporary schema for each run, so set `TEST_DATABASE_URL` to a test database and run `cargo test --locked -- --include-ignored`. It checks concurrent idempotency, conflict, withdrawal and replay, ranking threshold/order and receipt-time filtering, and signed Google-token backup isolation. Do not reuse a production database for tests.

For a loopback-only async load run against an isolated server instance, set `RATE_LIMIT_PER_MINUTE=1000000` and `RATE_LIMIT_MAX_CLIENTS=100000`, then run `cargo run --release --example loadgen -- http://127.0.0.1:8080 32 2000`. The generator refuses non-loopback URLs, measures ranking GET and unique POST plus receipt DELETE latency, and reports throughput and p50/p95. Use only a disposable database because it writes and deletes test batches.

This is account-free aggregate sharing, not anonymous transport. A lost app receipt cannot be recovered through an account, and the operator cannot establish that separate batches represent separate people.
