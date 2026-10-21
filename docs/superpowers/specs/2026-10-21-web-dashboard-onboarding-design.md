# Web community Dashboard and optional mobile setup

The user approved a Chinese web Dashboard in the existing Rust/Docker service
and added an optional setup wizard when the mobile app opens. Occupation and
computer proficiency may accompany explicitly reviewed anonymous contributions.

## User flow

The first production mobile launch shows a short setup page before Home.
Profession and proficiency are optional. Finish and Skip both allow normal app
use; completion is remembered on this device. Settings can reopen setup later.
Setup does not enable sharing or upload anything. The existing Dashboard opt-in
and per-batch preview remain the only path to publishing usage. The preview
defaults to the locally saved choices and permits either choice to be omitted
or changed for that batch. Pending retries retain their original metadata.

Store setup in the existing backup-excluded private usage directory. Keep it
separate from shortcut Profiles, Google backup, credentials and click history.
Clearing click history does not reset optional setup choices. Storage errors
must permit using Home without silently publishing or repeatedly blocking it.

## Shared contract

Keep schema_version 1 and existing optional `tag` profession values:
software_engineering, design, video_editing, office, other. Add optional
`experience` with beginner, intermediate, advanced. Missing/null means omitted.
No free text, inferred attributes, account IDs or stable installation IDs.

POST /v1/contributions accepts `experience`. GET /v1/rankings accepts optional
`experience` alongside period=all|7d|30d and optional tag, and echoes experience
as null or the requested value. Combined filters mean their intersection.
Keep the old canonical idempotency hash exactly when experience is absent so
previous pending batches can retry. Experience is part of the hash when present.
Withdrawal removes all derived totals exactly once. Existing global/tag totals,
UTC receipt-date windows and the three-batch per-category publication threshold
continue to apply. A batch is not a verified unique person.

An idempotent incremental PostgreSQL migration preserves existing data and adds
experience and combined-filter aggregates/indexes; avoid scanning the batch
journal for public reads. Extend transactions/functions so concurrent duplicate
submissions and withdrawals retain atomic totals. Legacy SQL entry points and
HTTP requests without experience continue to work.

Dart shared API: `communityExperienceLevels` is a Map<String,String>.
CommunityPendingBatch and CommunityRanking add nullable `experience`.
fetchRankings(String period, {String? tag, String? experience}) supports both.
Old local pending records and unfiltered legacy responses remain readable.

New lib/data/community_setup_repository.dart owns:

```dart
class CommunitySetupPreferences {
  const CommunitySetupPreferences({
    this.completed = false, this.profession, this.experience,
  });
  final bool completed;
  final String? profession;
  final String? experience;
}
class CommunitySetupRepository {
  CommunitySetupRepository({Future<Directory> Function()? directoryProvider});
  Future<CommunitySetupPreferences> load();
  Future<void> save(CommunitySetupPreferences preferences);
}
```

Missing file returns defaults; validate allowlists, atomically persist and
recover interrupted writes. Dedicated gate/widget tests exercise production
setup. Existing App tests injecting a controller can keep their established
Home fixture without the first-launch gate.

## Web UI

Rust embeds and serves the page at / and /dashboard with same-origin local CSS
and JavaScript, no frontend runtime service or external CDN. Chinese interface,
dark/cyan visual language, responsive phone and desktop layouts. Provide
published click total, published category count, first-place shortcut, period,
profession/proficiency filters, count chart/table, refresh and last refresh time.
Summaries describe only published rows. Do not sum category contribution counts
into a purported unique-person or total-batch statistic.

Handle loading, genuine empty data, invalid filters, unavailable service and
rate limiting visibly. Cancel/ignore obsolete requests after filter changes.
Render response text safely, add appropriate content types, asset caching and
security headers. No login, personal backup data or administrative credentials
are exposed by the public page. Existing API routes and production HTTPS stay
compatible. The local Docker endpoint remains 127.0.0.1:18443.

## Acceptance

Test private setup persistence/skip/reopen/failure, no automatic upload, payload
exclusions, metadata preview/retry persistence and combined filter requests.
Run Rust format/strict Clippy/full PostgreSQL HTTP tests with legacy retry and
all experience/tag intersections, invalid levels and withdrawal/concurrency.
Check the web page in a real browser at phone/desktop sizes, including empty,
filtered data and error handling; use a separate disposable DB for fixtures.
Build Android and check iOS CI, preserve the running PostgreSQL volume while
rebuilding/replacing only the API container. Commit/push the reviewed changes
on existing main, verify remote SHA and clean status.
