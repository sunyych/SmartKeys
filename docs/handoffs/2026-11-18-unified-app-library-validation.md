# Unified App library — implementation and acceptance

## Scope and versions

Implementation: `6894bbedfcbab6e5f46d39bf2671935ce7309a3a` on
`codex/unified-app-library`, based on main `2288c78`.
Full / Desktop are **1.8.0+10**; independent Android Bluetooth Lite is **1.3.0+4**.
See [App library usage](../APP_LIBRARY.md) and the
[design](../superpowers/specs/2026-11-18-unified-app-library-design.md).

The registry associates **60 Apps / 111 libraries** with canonical artwork.
There are **501 assigned defaults** and **825 explicitly unassigned template
actions**. Templates are not advertised as working defaults. Availability is
explicit: 54 macOS, 57 Windows and 29 Linux App/context entries. Safari, Finder
and Sketch have only a macOS variant. A Windows/Linux family can be Windows-only.

Canonical registry and server mirror SHA-256:
`b55306093d3bebf98005bc93d4f632934e096525bce245eb5bdc08280c7a2f5a`.
Runtime catalog serialization SHA-256:
`a17092264e0895350787ff715d102919a733392786d16ebaf57d44b83144c2f5`.
Generated mirrors have explicit LF attributes for reproducible Windows/Linux
checkouts. Artwork original bytes, hashes and terms are unchanged.

Desktop installs an icon association and profile in one manifest transaction,
using its actual OS. Add-copy is the default. Explicit replacement preserves
edited actions, deleted defaults, ordering and additional user actions. Imported
packages are bounded, registered, keyboard-only publications with matching PNG
hashes. Online-only artwork must accompany installation. Source metadata never
grants native launch authority. Managed Apps retain foreground guards; other
profiles require manual focus. Full receives profiles from Desktop and previews
the library without implicit configuration writes.

Lite installs only bundled libraries offline, after explicitly selecting the
controlled computer OS. Installation adds a new profile and never overwrites
existing profiles or private Launchpad combinations. Unassigned actions send no
input and can be configured locally. The twelve-key landscape surface, media,
pointer and saved keyboard launch combinations remain; KVM, voice and network
permissions are absent. Display labels use Command/Option and actual punctuation,
while the underlying execution keys and downloaded JSON remain unchanged.

## Local verification

| Check | Result |
| --- | --- |
| Full analysis / complete Flutter suite | clean / 336 passed |
| Desktop analysis / complete Flutter suite | clean / 146 passed, 1 Linux-only test skipped on Windows |
| Lite analysis / complete Flutter suite | clean / 82 passed |
| Shared protocol complete suite | 32 passed |
| Rust service / load generator | 35 passed / 1 passed; 3 PostgreSQL tests require CI |
| Rust formatting and clippy | clean, including `-D warnings` |
| Python App registry / icon registry / source exporter / Full APK guard | 8 / 8 / 5 / 10 passed |
| Independent Lite Python checks | 11 passed |
| Browser key-label assertions | 11 passed |
| Actual local browser App and legacy icon verification | both passed |
| Actual server downloads decoded by Desktop | all 60 bundles, 111 libraries |

Tests cover OS filtering, wrong family/type rejection, unsupported payloads,
immutable downloaded bytes, persistence rollback, add-copy, replacement with
edits/deletions, unknown launch-only Apps, unassigned no-input behavior, private
launch-key preservation, actual settings navigation, text scaling and overflow.
Browser tests include real package downloads, immutable URLs/ETag 304, read-only
405 responses, 503 recovery, malformed command rejection and 390px layout.

All three local optimized builds used fresh NTFS exports, with temporary drive
mapping ownership checked before cleanup. Packaged Android AOT was inspected in
all three ABIs; metadata alone was not accepted. The final Full binaries contain
the new Desktop setup guidance and omit the previous implementation explanation.
Runtime source comparisons matched 175 Full files, 91 Lite files and 105 Windows
files. Both Android packages and the Windows bundle contain the expected fifty
PNG hashes and LumiaKey branding.

## Hosted checks for the implementation commit

All five source-commit workflows succeeded:

- [Full Android and Windows installer](https://github.com/sunyych/SmartKeys/actions/runs/44273261949)
- [Independent Bluetooth Lite](https://github.com/sunyych/SmartKeys/actions/runs/44273261906)
- [iOS and macOS](https://github.com/sunyych/SmartKeys/actions/runs/44273261886)
- [Linux Desktop](https://github.com/sunyych/SmartKeys/actions/runs/44273262031)
- [Service, real PostgreSQL, Docker and browser checks](https://github.com/sunyych/SmartKeys/actions/runs/44273261884)

These include native Android unit tests and the three PostgreSQL integration
tests that were not run against a local database. macOS and iOS artifacts were
inspected after download, including actual version metadata, fifty icon hashes
and current App-library compiled markers. iOS kernel code also contains the new
setup guidance. macOS DMG structure and Linux archive paths/modes were checked.

## Installation and artifacts

The authorized Moto g play received same-certificate `adb install -r` upgrades,
without uninstall, downgrade, data clearing or permission grants. Final package
versions are Full 1.8.0/code 10 and Lite 1.3.0/code 4. Root visually inspected the
physical landscape Home, real settings entry, OS-aware App library and Chrome
macOS preview in both editions. The preview displays **Command + T**. Lite's
existing three profiles and twelve launch slots were retained. No shortcut,
media or launch button was activated and no configuration was saved during this
physical preview exercise. Existing host selection and diagnostics preferences
were not changed.

Windows Setup came from the exact implementation CI run. Installation returned
exit code 0 and installed payload FileVersion **1.8.0+10**. Both existing roaming
configuration directories were backed up before upgrade. Normal interactive
startup was used for the running application. Its read-only service check passed:
unauthenticated requests were denied, authenticated info/manifest returned 200,
twelve launcher slots were present, launch-only executable paths were excluded,
and the native Chrome PNG and conditional ETag request passed. No configuration
or input action was issued through this check.

Final local Android artifacts:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `LumiaKey-Full-1.8.0-Android.apk` | 158553873 | `b2b2efe2a10d572bc728727d970e76d12783c0b9510ebc612c6a5adbce098243` |
| `LumiaKey-Bluetooth-Lite-1.3.0-Android.apk` | 54054724 | `e5751e55b3655189a584fdccac291c29934090d7aaf6c48d72dd820f4c27fd0a` |
| `LumiaKey-Desktop-1.8.0-Windows-Setup.exe` | 17883672 | `31d3bff5dcf642517699a0029bdf6906d034fc2aa6e5f30a603d27393871fb6b` |

Android uses the existing development certificate with release optimization;
certificate SHA-256 is
`1136bc3a6e1408d11013e7e3d9e2c9dc4ca716da2cfc2887a3c82944956af7b8`.
The Windows installer ProductVersion is 1.8.0; its own numeric version resource is
zero/unspecified, while the installed application payload carries build 10.

The delivery directory is `build/artifacts/1.8.0/`. Its generated index, delivery
manifest and SHA256SUMS record actual packages and the final main integration
receipt. They include optimized Android APKs, Windows Setup/portable ZIP, macOS
DMG, Linux x86_64 tar.gz, unsigned iOS `.app` ZIP and separate Full/Lite source
ZIPs. This Linux run did not produce deb or AppImage. Windows is unsigned, macOS
is unnotarized and the iOS archive is an unsigned debug build, not an installable
signed IPA. No Mac/Linux/iOS physical-device acceptance is claimed.

Standalone source ZIPs exclude Git metadata, build output, private signing
material and local SDK settings. Only the two existing public Rust test-key
fixtures are permitted through the key filter. Unix shell wrappers are archived
with executable modes and LF line endings, with original and archived hashes
recorded separately; original artwork bytes are never normalized.

The screenshot archive distinguishes 154 Flutter widget renders, 16 real browser
captures and 15 physical-phone captures. Generated images were checked through
metadata/integrity and layout assertions without individual visual review;
physical phone review is recorded separately. Raw UI XML, pairing tokens and
configuration backups are not part of the delivery archives or Git commit.

## Remaining operational boundaries

The App platform implementation and local browser acceptance are complete. No
public deployment target/domain was supplied; no new public infrastructure,
submission/admin system, tags or GitHub Releases were created. App bundle imports
currently match the catalog shipped with the client; later registered catalog
publications require a corresponding client update.

Assigned defaults are curated from linked official documentation. Host App
preferences, versions, focus, keyboard layouts and meeting permissions can change
their behavior. The 501 third-party commands were not individually exercised on
physical Mac/Windows/Linux installations. The public validation format permits
single keyboard chords and explicit unassigned actions, never executable paths,
shell commands, native launch, macros, voice or KVM actions.
