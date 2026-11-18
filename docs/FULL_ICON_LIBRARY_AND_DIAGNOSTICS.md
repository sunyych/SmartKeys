# Full icon library and error diagnostics

Full/Desktop version: **1.6.0+8**. The independent Bluetooth Lite product has
its own local-only implementation and does not use the Full uploader.

The Settings icon library starts with the fifty generated offline resources.
`SMARTKEYS_ICON_URL` optionally configures the trusted HTTPS service origin.
An empty value means there is no online service; it does not imply a deployed
public endpoint. The compatible schema-1 registry can add new icon IDs without
rebuilding the app. An icon ID never grants application-launch or shortcut
permissions. Historical protocol `codex` artwork is explicitly adapted to
ChatGPT, rather than counted or searched as another brand.

Online PNGs use the configured origin, reject redirects, and must match the
registry SHA-256 and dimensions. Each image is at most 64 KiB and 512 pixels
per dimension. The persistent cache is separate from native computer icons,
scoped to its service origin, and limited to 100 images / 8 MiB with oldest
access first eviction. A changed hash invalidates memory and disk lookup;
late responses cannot publish bytes for a replaced registry entry. Native
computer artwork retains its authenticated, per-computer cache and 24-hour
expiry policy. Preview source links use the recorded official information
page, including when the original resource was extracted from Windows.

Full presents a new, optional error-sharing choice at first startup. Previous
community or usage consent is not inherited. Community controls remain in
Settings. Errors are stored locally by default; the capture API accepts only
the twenty fixed `DiagnosticCode` values. It accepts no raw exception, stack,
key, shortcut, input, app target, path, credential, or arbitrary context.
Successful input operations create no diagnostic event.

The local journal has a 1,000-event / 5-MiB hard limit and a seven- or thirty-day
retention choice, defaulting to thirty days. Startup and hourly maintenance
prune expired records and persist the result. Maintenance does not start
uploads. App metadata comes from the actual installed package; unverified
version/build metadata leaves sharing disabled.

`SMARTKEYS_DIAGNOSTICS_URL` separately configures the exact HTTPS
`/v1/diagnostics/errors` endpoint. It defaults to empty. It never uses the LAN
Desktop endpoint. Only new events in a durably authorized local epoch are
eligible. Journal persistence must succeed before an event can be sent.
Epochs stay local. Batches contain at most twenty sanitized events / 16 KiB;
the server must acknowledge the complete batch. Snapshot counts preserve new
occurrences that arrive while a previous count is in flight.

Automatic sharing makes one attempt and at most three retries (5 seconds,
30 seconds, 2 minutes). New failures do not reset an exhausted budget; the user
can explicitly retry. Upload failures do not recursively generate errors.
Turning sharing off immediately invalidates pending work and closes the
active HTTP client, then serially persists a deny marker and preference. A new
grant saves its epoch and journal before removing the marker. Clear uses the
same queue and cancellation boundary. Journal failures disable effective
sharing for the session. If revocation's marker succeeds while the preference
write fails, revocation remains durable; if all relevant storage fails, the UI
accurately reports that only the current session can be guaranteed off.

Regression entry points:

- `test/icon_library_test.dart`: real sixty-entry generated server registry,
  new online ID, actual PNG download, origin/hash checks, restart, eviction and
  refresh/download races.
- `test/diagnostics_service_test.dart`: real loopback HTTP only, exact wire
  fields, hostile errors, consent races, in-flight cancellation, bounded
  retries, persistence barriers, disk round trip and idle expiry.
- `test/icon_diagnostics_ui_test.dart`: search/preview/empty, narrow viewport
  and larger text, artwork invalidation, consent/log controls and current UI
  captures. Screenshot fixtures never submit genuine diagnostics.

Current captures are under
`build/handoff-1.6.0/screenshots/phone/full-icon-library-*.png` and
`full-error-*.png`. These are Flutter widget renders, not physical-device
captures or proof of a publicly deployed service.
