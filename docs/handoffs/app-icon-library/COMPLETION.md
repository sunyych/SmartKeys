# App icon library and diagnostics: completion validation

Validated on 2026-11-17 (America/Los_Angeles). Full mobile and Desktop are
**1.6.0+8**; independent Android Bluetooth Lite is **1.1.0+2**.

## Delivered behavior

- Fifty distinct offline application PNGs are generated from one authoritative
  catalog for Full, Desktop and Lite. The server has ten additional real icons.
  Sources, original bytes, terms references, dimensions and SHA-256 are recorded.
- Full and the website support searchable catalogs and downloads. Full checks
  origin, format, dimensions and hashes, and bounds its independent disk cache.
  Native computer artwork retains priority. Historical `codex` compatibility is
  explicitly separate from the ChatGPT/Codex product identities.
- Full error diagnostics have separate, optional consent, initially off. Only
  fixed codes and bounded metadata can be captured. Consent, revocation, durable
  writes, concurrent acknowledgements, finite retries and retention are tested.
  Lite has only local error logs and the offline gallery, with no uploader or
  Internet/microphone permission. Successful input creates no diagnostic events.
- Full retains landscape-only twelve-key controls, the touchpad, Desktop-owned
  launcher settings and the latest main branch's QR pairing/keyboard-inset fix.

Implementation and operational boundaries:
[Full diagnostics](../../FULL_ICON_LIBRARY_AND_DIAGNOSTICS.md),
[artwork provenance](../../APP_ICON_SOURCES.md),
[current editions](../../EDITIONS.md).

## Verification

| Check | Result |
| --- | --- |
| Full local suite | 324 passed; final cache-only correction additionally passed 14 focused tests |
| Full repository analysis | No issues found |
| Desktop local suite | 99 passed; one Linux-only audio test skipped on Windows |
| Independent diagnostics core | 8 passed |
| Lite original and standalone source | 26 passed; analysis clean |
| Android native | Full 16 passed; Lite 14 passed |
| Protocol / local dictation | 25 / 24 passed; optional model smoke remains skipped |
| Canonical artwork / safe exports / pinned CI font | 8 / 5 / 5 Python tests passed |
| Rust with real PostgreSQL | 29 server tests plus one load-generator test passed; no ignored tests in CI |
| Actual browser | 60 PNG hashes/dimensions, aliases, legacy URL, 304, copying, downloads, failures/retry and narrow layout passed |

The production implementation is commit `e48b975bcfea2209472ef1dfb57f62258f433c65`.
Subsequent `f61bcd5` and `1cd71f4` change documentation and CI preparation only.
The latter replaces a repeatedly stalled Ubuntu font-package download with one
official, commit-pinned and hash-verified Noto font. Runtime app sources and
the verified installation packages are unchanged by those CI commits.

| Hosted validation | Successful run |
| --- | --- |
| Full Android and Windows installer | [44225988327](https://github.com/sunyych/SmartKeys/actions/runs/44225988327) |
| iOS unsigned and macOS DMG | [44225988549](https://github.com/sunyych/SmartKeys/actions/runs/44225988549) |
| PostgreSQL, Docker and real browser | [44225988950](https://github.com/sunyych/SmartKeys/actions/runs/44225988950) |
| Linux with virtual PulseAudio | [44228808477](https://github.com/sunyych/SmartKeys/actions/runs/44228808477) |
| Lite sparse-checkout validation and Android build | [44228808390](https://github.com/sunyych/SmartKeys/actions/runs/44228808390) |

The final local Full APK matches 173 checked build-input files; the local
Windows bundle matches 96. Full Android, Lite Android, Windows, iOS and Linux
packages each contain the exact fifty expected PNGs and their recorded hashes.
The source exporter preserves independent projects, excludes build outputs and
signing material, and restores executable modes in source ZIPs.

## Installation and artifacts

The current Windows computer was upgraded to Desktop **1.6.0+8** using the
successful installer. Both existing configuration folders were backed up under
`build/installation-backups/1.6.0`. Installed-service checks passed: authenticated
200, unauthenticated 403, twelve launcher slots, unknown icon 404, and native
Chrome PNG with conditional 304.

The connected Moto G Play was upgraded in place using only `adb install -r`:
Full **1.6.0 / code 8**, Bluetooth Lite **1.1.0 / code 2**. Neither app's data
was cleared, no permissions were automatically granted, and the historical
shared-flavor Lite package was left intact. Verification does not authorize
diagnostic sharing or send shortcuts to the computer.

The combined current screenshot index contains **81** widget/browser renders:
22 Full, 30 Desktop, 21 Lite and eight website states. They are generated
captures; individual images were not manually inspected. Physical HID delivery,
other physical platforms and speech-recognition accuracy are outside this
verification.

Deliverables are under `build/artifacts/1.6.0`, with a build manifest and
per-file SHA-256. Android APKs use release optimization with the existing
Android Debug development certificate, not a store-production signing key.
Windows is unsigned, macOS is not notarized, and the iOS `.app` ZIP is unsigned
and needs Apple signing/provisioning before device installation.

No public center hostname was supplied. Icon and diagnostics HTTPS endpoints
remain explicit configuration values; no invented domain, public deployment or
real diagnostic submission was introduced. No tag, Release or new repository
was created. The verified feature includes the completed editions branch and
remote main `b6011ea` as ancestors for the authorized main merge.
