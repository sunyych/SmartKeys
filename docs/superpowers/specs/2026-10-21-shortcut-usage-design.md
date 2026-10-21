# Shortcut usage Dashboard and voluntary community ranking

Approved direction: the user requested local click history, a settings Dashboard,
period filtering/sorting, usage-based layout ordering and clear; then requested
voluntary anonymous uploads and an online common-shortcut ranking. On 2026-10-21
the user chose “按推荐方案开发 App 和可部署服务端”. Luna implements; the parent
agent reviews, validates, commits and pushes the existing main branch.

## Local experience

Record each nonempty shortcut press attempt once, including disconnected/failed
attempts; releases do not count. Retain existing local/remote/wheel entry points.
Store an event ID, local key/label, millisecond UTC timestamp and optional safe
public shortcut category. Events remain on the mobile device, separate from
Profiles, exports, Desktop requests and upload preferences. No silent retention
cap. Use a serialized append journal, recover complete lines after interruption,
and migrate existing aggregate counters without inventing historical events.
All-time statistics include migrated counts; dated views only include real events
and explain this distinction. Clear removes local counters and event history.

Use Android noBackupFilesDir and iOS Application Support with backup exclusion
for both usage and community submission receipts/preferences. Storage failures
must not prevent shortcut execution. Clearing/writing must be serialized so old
writes cannot resurrect cleared data. Preserve unrelated application settings.

Settings links to a dedicated responsive Dashboard: all time, today, last seven
calendar days, last thirty calendar days and inclusive custom date ranges;
summary counts; per-shortcut count ranking (descending/ascending) and latest-use
ranking; timestamped click history (newest/oldest). Use local dates for display
and UTC epoch milliseconds for persistence. Lists must support many events.
Bottom controls provide Smart sort (current local Profile, most-used first,
stable ties, empty buttons last) and confirmed Clear local usage. Smart sort is
an explicit action; usage never makes buttons jump while being pressed.

## Voluntary sharing

Default OFF. No background/automatic uploads. The user explicitly enables
sharing, previews the exact safe category/count summary and submits each batch.
Disable sharing at any time; read-only public rankings do not require sharing.
The only uploadable categories are these fixed IDs: copy, paste, cut, undo,
redo, select_all, save, find, new, open, print, new_tab, close_tab, bold, italic.
They represent recognized Ctrl/Command keyboard combinations. Unknown/custom
commands, Desktop JSON actions, labels, Profile IDs/names, URLs, paths, text,
device/account identifiers and precise click timestamps must never be uploaded.
Reject any action with nonempty arbitrary value. Legacy counts are local only.

Use one random batch ID and independent random deletion secret per submission,
without any stable installation identifier. Persist the pending batch before
network I/O and retry the identical batch after ambiguous failures; the server
must deduplicate atomically. Local event IDs associate acknowledgements with
eligible clicks and are NEVER sent. Already submitted/withdrawn clicks are not
submitted again automatically. Save receipts privately so users can withdraw
their contributions. Clear local usage and Withdraw online contributions have
separate, explicit scopes; clearing local history preserves deletion receipts.
Turning sharing off does not withdraw previously submitted aggregates.

Network infrastructure necessarily sees connection IPs; no IP, user agent,
account, device identifier or request body is stored in the application DB or
access logs. UI must not promise network anonymity. This is account-free
aggregate sharing. Lost/uninstalled receipts cannot be recovered by an account.

## API contract (v1)

The App uses compile-time SMARTKEYS_RANKING_URL, empty by default. Empty means a
clear service-not-configured state, never fabricated community data. Production
requires an HTTPS origin; loopback HTTP is allowed only through an explicit
test/development constructor. Use bounded responses, timeouts and no redirects.

POST /v1/contributions, JSON exact fields:
`{"schema_version":1,"batch_id":"<32 lowercase hex>","delete_token":"<64 lowercase hex>","items":[{"shortcut_id":"copy","count":2}]}`.
Items unique by category; 1..15 items; counts are positive integers, total <=
100000; body <=16384 bytes. Response 201 (new) or 200 (identical retry):
`{"schema_version":1,"batch_id":"...","status":"accepted"}`.
Conflicting same-ID payload returns 409; withdrawn batch cannot be resurrected
(410). Unknown fields/IDs, boolean/noninteger counts and malformed JSON fail.

GET /v1/rankings?period=all|7d|30d returns
`{"schema_version":1,"period":"all","updated_at":"<UTC ISO8601>","rankings":[{"shortcut_id":"copy","count":10,"contributions":3}]}`.
Sort count descending, ID ascending for ties. Publish a category only after
three separate submitted batches, explicitly called contributions, never unique
users. Period refers to time contributions were received, not private click
timestamps. Public results contain only category and aggregate counts.

DELETE /v1/contributions/<batch_id> authenticates using Authorization: Bearer
<delete_token>. Returns 204, including an authenticated repeated delete; wrong
secret fails. Remove item counts atomically, retain minimal batch tombstones
for replay prevention. A user can withdraw all receipts held by this install;
failed withdrawals retain receipts for explicit retry. Health endpoint GET
/healthz has no personal data. Client upload cancellation/opt-out must not
silently start or resume another upload.

## Deployable service

Dedicated Rust Axum/Tokio application and PostgreSQL with an async connection pool,
transactions, body/schema limits, bounded in-memory rate limiting, tests and a
Docker deployment using a nonroot Rust binary behind Caddy HTTPS. No public database port;
database data persisted in a dedicated PostgreSQL volume. API access logging disabled in both
application server and proxy. No third-party analytics. Document domain/TLS,
App endpoint build configuration, backup responsibilities and limitations of
account-free submissions (not a verified unique-user or fraud-proof ranking).
Do not deploy to an invented host or claim a real public service exists.

## Agreed interfaces and ownership

Local coder owns lib/data/shortcut_usage_repository.dart, new
lib/data/private_usage_directory.dart and lib/data/public_shortcut_catalog.dart,
AppController, app.dart, native mobile channel changes and local/controller
tests. Expose ShortcutUsageEvent {String id, key, label; int usedAt;
String? publicShortcutId}, repository events (oldest first), hasLegacyCounts,
recordsForPeriod({DateTime? start, DateTime? end}) with exclusive end,
record(key,label,{String? publicShortcutId}), and flush(). Keep existing records,
countFor, load and clear APIs and test-friendly memory implementation.
Expose Future<Directory> privateUsageDirectory() in private_usage_directory.dart.
Expose const publicShortcutLabels (Map<String,String>) and
String? publicShortcutIdForAction(HidAction action) in public_shortcut_catalog.dart.

UI/sharing coder owns new usage_dashboard_screen.dart and community sharing
data/client files, SettingsScreen, and Dashboard/sharing tests. It consumes the
above interfaces, injects network/directory dependencies in tests, and does not
modify controller/app/native files. It may retain existing settings usage
summary, but must replace misleading “never leaves” text with opt-in explanation.

Server coder owns community_server/** including Rust tests, API and deployment docs.
Parent reviews cross-boundary contracts and runs full validation.

## Acceptance

Meaningful tests cover journal restart/migration, date boundaries, rapid writes
and clear, local-only payload exclusions, default-off/no automatic network,
preview/consent, idempotent retry/restart, withdrawals and races, ranking period/
sort/empty/error states, HTTP/schema limits and concurrent duplicate requests.
Measure real local HTTP concurrency throughput and p50/p95 latency for uploads and ranking reads. Run all four existing Dart package suites with coverage, analysis, Android native
unit checks and Android build; add server tests and a real local HTTP client/API
round trip. Inspect phone/tablet Dashboard screenshots. Report measured coverage
and platform/deployment limits; preserve unrelated work; commit/push main and
verify the remote SHA. iOS native acceptance requires macOS and physical device.

## Selective Google account backup (user addition)

The user requested Google-account-bound online settings backup, then specified
independent selection of App settings, individual shortcut Profiles and optional
custom images. They have no OAuth client IDs yet and explicitly chose a
configurable implementation and integration instructions. Use google_sign_in
7.2.x on mobile, explicit sign-in, sign-out and explicit backup/restore/delete.
No automatic backup, no Google Drive scope, no silent linking to anonymous
rankings. Display selected account and the selected backup contents before PUT.
Anonymous requests never carry Google tokens. All Google tokens stay in memory;
the SDK manages its own session. The backup DB is keyed by verified Google `sub`,
not email or user-supplied identity; store no raw token/email/device information.

Server configuration GOOGLE_CLIENT_IDS is a comma-separated allowlist of Web
OAuth client IDs. The App takes SMARTKEYS_GOOGLE_WEB_CLIENT_ID,
SMARTKEYS_GOOGLE_IOS_CLIENT_ID and SMARTKEYS_BACKUP_URL (HTTPS; may use ranking
origin). iOS additionally requires the corresponding URL scheme registered in
Info.plist. Missing/mismatched client setup must produce an unavailable state
before invoking Google SDK authentication, which can crash on native bad setup.
Android needs the correct package/signing SHA OAuth registrations, documented.
No client secret is needed or committed. A verified Google ID token is the
Bearer token for each backup request; expiration requires explicit re-sign-in.
Validate Google's RS256 signature, issuer, audience, expiry and nonempty sub
using cached official JWKS, bounded HTTPS and a mature JWT library. Do not use
tokeninfo as production authentication. Backup unavailable/503 if unconfigured;
public ranking/local controls continue to work.

### Account backup API

All routes `/v1/account/backup` require verified Google Bearer auth. One latest
snapshot per account. PUT replaces only that account's snapshot atomically.
Body limit 20 MiB (encoded JSON), images optional, no request/authorization logs.
PUT exact envelope:
`{"schema_version":1,"selection":{"settings":true,"profile_ids":["profile_general"],"images":false},"data":{"preferences":{...},"profiles":[...],"images":[]}}`.
`selection` exact keys settings:boolean, profile_ids:unique string array <=4,
images:boolean. At least settings or one Profile must be selected. data exact
keys preferences (AppPreferences object if settings, otherwise null), profiles
(selected ProfileConfig.toJson objects in selection order, <=4, <=60 unique
positions each), images (array described below; empty when not selected).
All profile IDs exactly match profile_ids, no device/config/usage/receipt fields.
preferences exact allowlisted current AppPreferences.toJson keys and types.
Profile/button/visual/wheel/action objects use only current model toJson keys;
reject unknown keys recursively. Device/defaultHost/Google/connection tokens,
usage history and anonymous consent/receipts never enter backup. Permit typed
keyboard/mouse/media/none actions. Preserve companion action values as private
account data when each value is a nonempty JSON object encoded in at most 16 KiB
of UTF-8; require null keyCode and an empty modifiers list. Validate but never
execute companion commands during backup or restore. Custom images use safe relative paths only: images/<safe folder>/
<safe filename> with png/jpg/jpeg/webp extension, no traversal/absolute paths.
Each image object has exact keys path,mime_type,data_base64; <=4 MiB decoded per
image, <=244 images, no duplicate paths. Validate known MIME/format signature,
base64 and size, and allow only images actually referenced by selected Profiles.
All model timestamps remain configuration timestamps, never usage timestamps.

PUT success 200: `{"schema_version":1,"updated_at":"<UTC ISO8601>"}`.
GET success 200: `{"schema_version":1,"updated_at":"...","backup":<PUT envelope>}`;
404 if no snapshot. DELETE 204 idempotent for the same authenticated account.
Invalid auth 401, unavailable config/JWKS 503, invalid payload 400/413. Never log
body/JWT/subject. Tests must exercise forged/expired/wrong-audience IDs and
two-account isolation, using signed local JWKS fixtures (not unverified user IDs).

Restore offers selection of settings, individual Profiles and images from the
downloaded snapshot. Apply Preferences only when selected. Merge Profiles by ID,
preserve unaffected local Profiles/device pairing, stable order and existing
active/default choice; fail before mutation if additions exceed four slots.
Do not auto-execute restored actions. Restore images only beneath the private
image root, validating paths/bytes before atomic writes and config replacement.
When images are omitted/unavailable, retain only references that resolve locally;
otherwise clear their visuals and explain this in preview. Save config before
updating controller state and apply runtime orientation/charging preferences
without sending Desktop/keyboard commands. Local usage and upload receipts stay
unchanged through backup, restore and account sign-out.

Luna local coder takes Task 4 after local history: new Google auth service,
selective backup serializer/client, backup screen, controller restore method,
pubspec/lock and necessary native iOS OAuth configuration, focused tests and
docs/GOOGLE_BACKUP.md. UI coder only adds the Settings link once the screen exists.
Server coder adds independent auth/account_backup modules, migrations and tests.

Implementation references: [Google ID-token verification](https://developers.google.com/identity/sign-in/web/backend-auth),
[Flutter Google sign-in](https://pub.dev/packages/google_sign_in),
[iOS integration](https://pub.dev/packages/google_sign_in_ios),
[Android no-backup storage](https://developer.android.com/identity/data/autobackup),
[Apple backup exclusion](https://developer.apple.com/documentation/foundation/urlresourcekey/isexcludedfrombackupkey).

## Optional profession tags (user addition)

The user requested optional tags such as software engineer and designer for
public shortcut rankings. Provide fixed IDs software_engineering, design,
video_editing, office, other; no free text or inferred profession. Default is
no tag. A per-batch preview optionally selects one tag, without Google sign-in
or identity linkage. Do not require a profession for local use or reading the
overall ranking. Read filters and contribution tags are independent controls.

POST /v1/contributions accepts an additional optional `tag` string (one of the
IDs) or null/omitted for no tag. Include the canonical optional tag in the
payload hash; a saved retry cannot change its tag. GET /v1/rankings accepts an
optional tag query; absent means all contributions, selected means only that
tag. The response echoes `tag`: null or the requested ID. Unknown tags are 400.
Retain global totals/daily totals and maintain indexed per-tag totals/daily
totals in the same accept/withdraw transaction. The minimum three-batch
publication threshold applies independently to each category/tag view. The
time windows are the most recent seven/thirty UTC receipt calendar days.
Never label batch totals as unique users. Test default-none compatibility,
tagged/global counts, filtering, idempotency conflict and withdrawal isolation.
