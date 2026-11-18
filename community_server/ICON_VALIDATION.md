# Icon catalog and web verification

Validated locally on 2026-11-17 with Rust 1.98.1 and an existing Edge/Playwright
runtime. No browser packages were installed for this local run.

## Catalog contract

The same Rust dashboard service exposes `/icons`, `/v1/icons/catalog`, and
`/v1/icons/{app_id}`. Catalog schema 1 contains **17 IDs representing 16
canonical brands**. `codex` is only the historical combined ChatGPT alias;
its `canonical_id` is `chatgpt`, and it is not counted as another brand.

All 17 registered download routes return bundled PNG data bounded to 64 KiB
and dimensions at most 512 by 512. Content types are `image/png`, with
`nosniff`, a fixed PNG filename, and cache headers. The API never fetches an
arbitrary supplied URL. Unknown IDs, traversal strings and external-URL strings
return 404.

Claude uses the Claude-specific asset, not the Anthropic corporate wordmark.
SOLIDWORKS uses a 16-pixel official support-site favicon as a documented
low-resolution fallback, not the old Dassault corporate asset. The web page
calls out this limitation and prioritizes installed native application icons.
Actual sources and brand/license boundaries are in
[`docs/APP_ICON_SOURCES.md`](../docs/APP_ICON_SOURCES.md). Source links and the
project's open-source license do not establish trademark or brand permissions.

## Actual checks

- `cargo fmt --check`: passed.
- `cargo clippy --locked --offline --all-targets -- -D warnings`: passed.
- Server tests: **23 passed, 2 PostgreSQL-only tests ignored locally**.
- Load-generator example: **1 passed**.
- Real browser verification passed: all PNG downloads and bounds, legacy alias,
  source links, ID/name search, a real download interaction, unknown-ID empty
  state, **390-pixel viewport without horizontal overflow**, injected HTTP 503
  error and successful retry recovery, and no JavaScript page errors.

The hosted `community-server` workflow runs both PostgreSQL tests with
`--include-ignored`, verifies the Docker build context, and runs the browser
checks. Those hosted results must be observed separately; local skipped tests
are not presented as PostgreSQL validation.

Local raw results:

- `build/handoff-1.5.0/logs/community-server-tests.log`
- `build/handoff-1.5.0/logs/web-icon-browser.log`
- `build/handoff-1.5.0/logs/web-icon-browser-report.json`

Five current browser captures and compatible metadata are stored beneath the
shared screenshot root in `web/`: `web-icons-catalog`, `web-icons-search`,
`web-icons-unknown`, `web-icons-mobile`, and `web-icons-error`. The error capture
explicitly documents its injected 503. The task-owned localhost preview was
stopped after verification.

## Reproduce browser checks

Start the same server in icon-preview mode, which does not need PostgreSQL:

```sh
LISTEN_ADDR=127.0.0.1:18741 cargo run --manifest-path community_server/Cargo.toml --locked -- --icons-preview
```

In another shell run `node community_server/tests/browser_icons.cjs`. The script
uses `PLAYWRIGHT_MODULE` when the package is provided externally, and optional
`BROWSER_EXECUTABLE_PATH` for an existing browser. `ICON_BASE_URL`,
`SMARTKEYS_SCREENSHOT_DIR`, and `WEB_REVIEW_REPORT` configure the local endpoint
and output locations. No user-specific paths are embedded in the script.
