# App icon library and error diagnostics design

This implements the user's approved handoff under `docs/handoffs/app-icon-library` and their latest instruction to finish both feature branches and merge into main. The older handoff's no-main restriction is superseded by that instruction. The validated editions integration and main's QR pairing are retained.

## Products and ownership

Full and Desktop become `1.6.0+8`; independent Android Bluetooth Lite becomes `1.1.0+2`. Full retains twelve Desktop-owned slots, landscape-only controls, activation/session protection and QR pairing. Icon browsing never grants application-launch or shortcut permissions. Lite remains Bluetooth/local-only, with no network, microphone, cloud account, launcher or diagnostics uploader.

Luna owns original artwork, authoritative catalog, generation and Rust icon/web service. Luna interface owns Full icon browsing/cache and Full diagnostics storage/consent/uploader/UI/instrumentation. Luna platform owns the pure diagnostics core, its self-contained Lite vendor copy, Lite local UI and Rust diagnostics endpoint. The primary agent reviews, verifies, commits and merges.

## Icons

`packages/app_icon_catalog/catalog.json` is authoritative. It contains the required fifty unique built-ins and ten genuine online-only resources. The handoff permits reliable-source substitutions among the ten examples; Brave replaces inaccessible FileZilla. Aliases do not increase counts. Every asset records original source, source page, terms/provenance limits, retrieval time, source/output hashes and dimensions. Native Windows Explorer extraction is accurately identified as an installed OS resource, with binary version/hash and an official documentation link.

Prepared resources are 256×256 RGBA PNG, rendered with uniform contain scaling, transparent padding and preserved artwork. No fabricated logos, cropping, stretching or repeated alias resources count toward fifty. The complete set must decode, have distinct output hashes and remain below 64 KiB per image.

The generator creates self-contained `lib/icons/builtin_icon_catalog.g.dart` and fifty PNGs in Full, Desktop and Lite; the server receives all sixty. Generated API: `BuiltinIconEntry` with `id`, `name`, `aliases`, `assetPath`, `sha256`, `version`, source/terms fields and dimensions; `builtinIconCatalog`, `builtinIconById(String)` and `canonicalBuiltinIconId(String)`. Legacy protocol `codex`→ChatGPT adaptation is explicit and separate from ordinary product identity/search.

The existing Rust `/icons` page and `/v1/icons` routes are extended. Existing catalog fields remain compatible; entries add aliases, version/hash, dimensions, terms and built-in status. Search matches names/IDs/aliases; deep links, copied IDs, full previews, actual downloads, empty/loading/error/retry states and narrow/keyboard layouts are covered. Registered fixed resources provide expansion independently of an App release; no URL proxy exists.

Full reads generated built-ins without network and resolves online entries from a configured HTTPS catalog. Resource paths are constructed on the configured origin; redirects and unexpected paths/types/hashes/dimensions are rejected. Central cache is separate from per-computer native icons, capped at 100 images/8 MiB with bounded catalog storage. Missing/corrupt/offline data falls back safely. Lite can search and inspect its fifty bundled entries but cannot fetch online resources. Desktop artwork uses the same generated mapping and preserves native-image priority.

## Local diagnostics and privacy

`packages/diagnostics_core` is pure Dart with no runtime dependencies or I/O/network imports. A generated/synchronized copy containing only production source and package metadata lives inside `apps/bluetooth/packages/diagnostics_core`, so exported Lite has no parent dependency.

`ErrorJournal` is constructed with validated `DiagnosticMetadata`. Its capture entry accepts only `DiagnosticCode` and an optional local consent epoch, never an exception, stack, message, request, context map or user input. Twenty fixed codes derive module, trigger, severity and display text. Event IDs are fresh UUIDv4; metadata is actual version/build, fixed edition and fixed platform.

Events contain first/last UTC milliseconds and bounded repeat count. Same code/metadata can merge within five minutes only inside one consent epoch. Local retention defaults to thirty days; the UI offers seven/thirty days. All settings retain hard limits of 1000 events and 5 MiB. Unknown persisted fields/invalid metadata are rejected. Storage failure leaves the bounded in-memory view usable and never recursively logs itself.

Full reads actual package version/build through the existing `package_info_plus` version. Lite gets only version/build from its native Android channel without a new network-capable plugin. Unavailable metadata cannot enable sharing with invented version values.

Full consent is new and independent of usage/community consent, initially undecided/off. The first-use choice accurately describes error diagnostics, offers local-only and allow, and can be dismissed. Community functions remain reachable through Settings. A durable new epoch precedes enabling uploads; only errors created afterward are eligible. Revocation synchronously invalidates the generation, cancels timers/requests/queues and preserves local records. Consent/tombstone persistence failures remain fail-closed in the session with accurate feedback. Clearing cancels pending work and changes the epoch.

Full upload uses a distinct, explicitly configured HTTPS center endpoint. It is never the paired Desktop address and has no default invented domain. Batches contain at most twenty events/16 KiB, with one active request and finite retries. Failed uploading does not generate more diagnostic records. Successful key, shortcut and pointer actions create zero diagnostics.

## Diagnostics API

`POST /v1/diagnostics/errors` accepts exactly `schemaVersion` and `events`. Each event accepts exactly `id`, `occurredAtMs`, `lastOccurredAtMs`, `appVersion`, `appBuild`, `edition`, `platform`, `code`, `repeatCount`. Epoch, arbitrary messages, input/shortcut/app IDs, credentials, paths, network addresses and device/user identifiers are forbidden. Only Full Android/iOS payloads are accepted. The response acknowledges accepted IDs; errors use fixed codes.

The backend revalidates UUID, time range, bounded metadata, code and count. ID metadata is immutable; duplicate counts/times use idempotent maxima and conflicting reuse returns 409. Transactions serialize capacity enforcement. Retention is thirty days and at most 100000 events globally, with bounded field lengths and rate limiting using nonpersistent anonymous buckets. No public read/dashboard/account-backup integration is added. Infrastructure can see network requests; the product never promises absolute network anonymity.

## Verification and delivery

Assets, code generation, app package contents, aliases and lack of command-allowlist changes are checked. Full extra-icon download/cache is exercised with real loopback HTTP, including offline reuse and tampering. Diagnostics tests cover default/refused/allowed/revoked/re-enabled consent, hostile error values, persistence/HTTP failures, concurrent occurrences/acknowledgements and finite retries. Rust tests include strict rejection, idempotency, retention/capacity and real PostgreSQL.

Each new interface/state receives current widget/browser captures under one new screenshot root and one index; images are not individually inspected. Full, Desktop, protocol, pure core, Lite, Android native, Rust and browser suites run, followed by artifact-only Android/Windows/Apple/Linux validation. Lite's exported source is independently analyzed/tested/built and its actual APK checked for forbidden permissions/dependencies.

After feature verification, fetch current main, merge any newer changes into the feature and revalidate affected targets. Commit/push the feature, merge it into main without losing QR pairing or earlier editions work, and push main. No tag, Release, new repository or public deployment is implied. If no real center URL is supplied, ship configurable endpoints and demonstrate the existing Rust service locally without sending real user diagnostics.
