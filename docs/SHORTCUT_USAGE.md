# Shortcut usage and community ranking

Open **Settings → Usage Dashboard**. Each nonempty shortcut press records one
click attempt and its time; releases are not counted. A disconnected or failed
shortcut attempt still counts as a click. Phone Profile buttons, wheel steps,
Desktop buttons and app-launch taps retain their existing recording entry points.

The Dashboard offers all time, today, seven/thirty local calendar days and custom
inclusive dates. Rank shortcuts by most used, least used or latest use, and
inspect click history from newest or oldest. Older versions stored aggregate
counts without timestamps: migration preserves their all-time counts, but dated
views cannot recreate their past click times.

**Smart sort** explicitly reorders the current local Profile by its lifetime
usage counts; ties keep position and empty buttons follow configured actions.
It does not reorder Desktop-managed layouts or make the layout jump during use.
**Clear local usage** confirms before deleting detailed history and counters.
Clearing local history does not delete online contributions or Google backups;
those have separate removal controls.

## Private by default

Detailed events, local shortcut keys/labels and precise timestamps stay in the
mobile journal. Android stores it beneath noBackupFilesDir; iOS stores it in
Application Support with backup exclusion. They are absent from Profile exports,
Desktop requests and Google account backups. Submission preferences and deletion
receipts use the same protected directory, separately from usage history.

## Optional community submissions

Sharing starts off. Enabling it does not start uploads: each submission requires
a preview and a manual confirmation. Only recognized standard shortcut categories
and their counts qualify. Custom names, Profile identifiers, URLs, text, paths,
raw Desktop commands, device/account identifiers and exact click timestamps are
excluded. Legacy aggregate counters cannot be submitted.

Contributions use random per-batch identifiers and deletion secrets rather than
a stable installation identifier. Pending requests are saved privately and
explicit retries use the same batch to prevent duplicate counts after an
ambiguous network failure. Saved receipts allow **Withdraw online contributions**;
keep them until withdrawal succeeds. Signing in to Google does not attach your
account to public submissions. Network infrastructure can see connection IPs;
this feature provides account-free aggregate sharing, not network anonymity.

Public rankings can be read without enabling sharing. A category appears after
at least three independent submitted batches, which are called contributions,
not unique people. Seven/thirty-day public rankings use the UTC calendar days
on which contributions reached the service; private click times are not sent.
The service is not a verified unique-person or fraud-proof popularity measure.

Profession tags are optional. In a submission preview you may select software
engineering, design, video editing, office work or other, or leave the tag empty.
This does not infer your occupation or bind it to your Google account. Public
ranking filters independently show all professions or one selected tag; the
three-contribution threshold applies to each filtered category as well.

## Service configuration

Build the App with `--dart-define=SMARTKEYS_RANKING_URL=https://<your-service>`.
Without an endpoint, the Dashboard clearly reports that community service is not
configured and continues to provide local statistics. Production endpoints must
use HTTPS. There is no bundled fabricated online ranking or default public host.
Deploy the [Rust/PostgreSQL service](../community_server/README.md) to provide one.

Google account backup is independent and manual. It offers selective settings,
Profiles and custom images, preview/restore, and account-specific online deletion.
See [GOOGLE_BACKUP.md](GOOGLE_BACKUP.md) for the required OAuth client setup.
