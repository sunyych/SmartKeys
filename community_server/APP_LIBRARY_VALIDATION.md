# App library local acceptance — 2026-11-18

The public App registry and web platform are implemented and verified locally.
There is no public deployment or assumed target hostname in this acceptance.

## Frozen publication

- Catalog version: `2026-11-18.1`.
- Canonical and Docker-contained mirror SHA-256:
  `b55306093d3bebf98005bc93d4f632934e096525bce245eb5bdc08280c7a2f5a`.
- Runtime catalog byte SHA-256 / ETag:
  `a17092264e0895350787ff715d102919a733392786d16ebaf57d44b83144c2f5`.
- 60 Apps, 111 libraries, 501 assigned single chords, 825 explicit unassigned
  actions. Availability: macOS 54 Apps, Windows 57, Linux 29.
- The canonical file was normalized from CRLF to LF after initial freezing.
  The registry values and runtime catalog bytes did not change.

The actual loopback HTTP catalog was compared structurally with the final
canonical data. All 60 actual server downloads were then parsed by the real
Desktop `AppLibraryBundle.decode` implementation, including all 111 libraries.
The common model normalizes field order before reviewed-record comparison.

## Results

| Check | Local result |
| --- | --- |
| Rust formatting | Passed |
| Clippy, all targets, warnings denied | Passed |
| Server unit and loopback HTTP suite | 35 passed; 3 PostgreSQL tests ignored |
| Load-generator unit test | 1 passed |
| New public App module | 9 tests, including all 60 bundle HTTP responses |
| Rust binary build | Passed |
| Desktop decoder against actual server downloads | 60 bundles / 111 libraries passed |
| App browser acceptance | Passed; 8 current screenshots |
| Platform key display formatter | 11 assertions passed; raw download keys unchanged |
| Existing icon browser acceptance | Passed; 8 current screenshots |

The three ignored tests require a disposable `TEST_DATABASE_URL`: existing
community HTTP/account isolation, experience migration, and diagnostics
capacity/retention. They were not run against any local or production database.
The updated community-server CI retains PostgreSQL with `--include-ignored`,
Docker-context validation, existing icon acceptance, and new App browser tests.
Hosted CI results must be checked separately after the reviewed commit is pushed.

Browser acceptance covers every bundle's registered PNG bytes, hashes, immutable
URL, conditional 304 and read-only 405 responses; a real downloaded JSON file;
platform-friendly Command/Option/Windows/Super and punctuation labels;
Safari/Finder availability; Windows-only availability within the shared keyboard
family; explicit unassigned actions; injected dangerous-action rejection; 503
download/catalog recovery; and 390-pixel App/dashboard navigation with no
horizontal overflow. Existing aliases, historical icon-only `codex` behavior,
PNG downloads, source/terms links and icon failure recovery remain covered.
Screenshots are headless Chromium fixtures and were not individually inspected.

## Evidence and reproduction

Local generated evidence is under `build/handoff-1.8.0/`:

- `app-library-final-validation.json`
- `desktop-server-bundle-interop.log`
- `web-app-browser-report.json`, `web-icon-browser-report.json`
- `screenshots/web/` (PNG files with JSON sidecars)

Rust logs are `build/handoff-app-library-{all-tests,clippy,build}.log`.

Start the database-free loopback preview with
`LISTEN_ADDR=127.0.0.1:19882 cargo run --locked -- --apps-preview` from this
directory. Run both `tests/browser_apps.cjs` and `tests/browser_icons.cjs` with
`APP_BASE_URL` / `ICON_BASE_URL` set to that origin and `PLAYWRIGHT_MODULE` pointing
to the installed Playwright package. `BROWSER_EXECUTABLE_PATH` optionally selects
an already-installed Chromium. No browser installation or public upload is part
of this feature's verification.

Public publication remains Git-reviewed static data. There are no new SQL
tables, submission/admin endpoints, execution methods, private-backup migrations
or cross-product consent changes. A package is inert configuration data.
