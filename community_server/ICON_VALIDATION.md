# Icon catalog and web verification

The current registry contains **60 unique products: 50 built-in and 10 online-only**.
The source of truth is `packages/app_icon_catalog/catalog.json`, with original
artwork, actual source/page/terms, retrieval date, original and prepared hashes,
dimensions and provenance. The offline standard-library generator emits
self-contained Full/Desktop/Lite maps and resources and a complete server context.
See [source and rights details](../docs/APP_ICON_SOURCES.md) and the
[maintenance instructions](../packages/app_icon_catalog/README.md).

## API contract

`GET /v1/icons/catalog` retains `schema_version: 1` and `icons`, adding catalog
`version` and a separate `legacy_aliases` section. Each product includes
`app_id`, `canonical_id`, `name`, `aliases`, `download_url`, `mime_type`, `source`,
`source_page_url`, `terms_url`, `license`, `available`, `bundled`, `sha256`,
`version`, `width` and `height`. The sixty normal records are unique products.
The historical `codex` value does not appear as an ordinary product/search alias.
Its old download URL remains compatible, returning the ChatGPT image with an
explicit `X-LumiaKey-Legacy-Icon` header; this is not the actual Codex product.

`GET /v1/icons/{app_id}` resolves only registered products/ordinary aliases or
that explicit historical adapter. It returns the actual 256px PNG and canonical
filename, `image/png`, `nosniff`, `Content-Location`, cache headers and the image
SHA256 as its ETag. Matching `If-None-Match` receives304 with no body; a previous
hash receives current PNG bytes. Unknown IDs/traversal/external URL strings are404.
The service never fetches a caller-provided URL. Source locations such as the
native Explorer resource remain accurately recorded; the user-facing source link
uses its separately recorded official HTTPS source page.

## Actual local evidence (2026-11-17)

- Generator `--check`: passed, with fifty images in each app and sixty in server.
- Generator regression suite: **8 passed** (counts/identity/source hashes,
  generated drift, PNG corruption, path containment and independent artifacts).
- Full Pillow decoding: **60 passed**, RGBA256×256; alpha bounds stay within
  centered16..240 content bounds;60 distinct SHA256 values. Maximum59,023 bytes,
  total1,047,665 bytes. No alias/placeholder counts, cropping or stretching.
- Focused Rust icon suite: **5 passed**, covering every resource/hash/header,
  alias separation, ETag304/stale versions, extras and unknown/proxy rejection.
- Real headless Chromium browser suite: **passed**. All60 PNGs/hash/dimensions,
  ETag caching, alias search, copied App ID, actual verified PNG download,
  extra online Brave resource, download503/retry, loading, unknown empty state,
  catalog503/retry, keyboard navigation,390px no horizontal overflow, zero page errors.
- Full server fmt/clippy/PostgreSQL checks are part of the shared integration
  run; consult its exact test log instead of treating this focused result as PG proof.

Current logs are under `build/handoff-1.6.0/logs/`:
`icon-assets-verification.json`, `web-icon-browser-report.json`, and
`web-icon-browser.log`. Eight browser captures plus sidecars are under
`build/handoff-1.6.0/screenshots/web/`: catalog, search, unknown, extra,
download-error, mobile, error and loading. Injected503/loading states are
identified in their metadata. No individual screenshot inspection is claimed.

## Expansion without an App update

Brave and the other nine records with `bundled:false` are absent from each
App's generated fifty-entry map/assets but downloadable from the existing server.
To extend the server, register another genuine original/terms/hash entry in the
canonical data, prepare its PNG, update the explicit online count and catalog version,
generate, review and deploy only the server catalog/assets. Already released
Full clients load configured-origin metadata and can download registered extra
IDs without a new App build. Bluetooth Lite remains strictly offline. Icons
never grant application launch or command permissions.

## Reproduce browser verification

```sh
LISTEN_ADDR=127.0.0.1:18741 cargo run --manifest-path community_server/Cargo.toml --locked -- --icons-preview
```

In another shell run `node community_server/tests/browser_icons.cjs`.
`PLAYWRIGHT_MODULE` can identify an externally supplied Playwright package;
`BROWSER_EXECUTABLE_PATH` optionally selects an installed browser.
`ICON_BASE_URL`, `SMARTKEYS_SCREENSHOT_DIR` and `WEB_REVIEW_REPORT` select local
endpoint/output locations. No user-specific paths are embedded in product scripts.
The hosted workflow runs canonical checks, Rust/PostgreSQL tests, Docker context
build and the same browser suite; hosted success must be observed separately.
