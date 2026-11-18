# Diagnostics core

Pure Dart fixed-code diagnostics. There are no runtime dependencies, I/O imports or network APIs. `ErrorJournal.capture` accepts only a `DiagnosticCode` and optional local consent epoch. Hosts own persistence, upload cancellation, consent and acknowledgement counts.

`DiagnosticMetadata` permits a missing version/build pair for local-only records; `toUploadJson` refuses such records and all Lite records. Restore is strict and rejects unknown fields. Events are immutable snapshots: acknowledge only the counts in the submitted snapshot, so newer merged occurrences remain pending. Upload JSON never contains the local epoch.

Defaults and hard ceilings: 1000 events, 5 MiB, 30 days. Retention may be reduced (the products offer 7 or 30 days). Oldest last-occurrence records are evicted first. Errors merge within five minutes only for the same code, metadata and consent epoch. Successful input operations do not call capture.
