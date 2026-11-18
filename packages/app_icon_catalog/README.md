# Authoritative application artwork

This data package is the single source for 50 built-in application icons and
10 additional web-only icons. It is not a Dart runtime dependency. The independent
Bluetooth edition receives copied, self-contained Dart data and the fifty PNGs;
it never needs this parent directory or a network connection.

`catalog.json` records identity/aliases, delivery cohort, original source/page,
owner terms, retrieval date, original and output SHA256, dimensions, normalization
and provenance exceptions. `sources/` preserves original artwork; `png/` contains
prepared 256×256 RGBA images. Third-party marks retain their owners' rights. This
repository does not grant a blanket artwork/trademark license; consult each
record's terms. See [source details](../../docs/APP_ICON_SOURCES.md).

From the repository root:

```sh
python scripts/generate_app_icon_catalog.py
python scripts/generate_app_icon_catalog.py --check
python -m unittest scripts/test_generate_app_icon_catalog.py
```

An isolated Full source export intentionally omits `apps/bluetooth`; use
`python scripts/generate_app_icon_catalog.py --full-only --check` there.
This explicit mode checks Full, Desktop and server without recreating Lite.
The default repository/CI mode always requires all four mirrors.
The repository's aggregate Actions also validate sibling projects; those jobs
are not advertised as a standalone CI template for an exported Full-only tree.
Use the explicit Full-only generation check and that export's build instructions.

The generator uses only the Python standard library, performs no network I/O,
and validates original/output hashes, complete PNG data, resource count and
alias uniqueness. It writes the same generated Dart API and fifty PNGs into
Full, Desktop and independent Lite, plus sixty PNGs/metadata and a generated
Rust registry into the server. Generated mirrors are not edited manually.
Only stale PNGs in those managed icon directories are removed; source vectors
and documentation remain untouched.

Generated Dart API: `BuiltinIconEntry`, `builtinIconCatalog`, `builtinIconById`,
`canonicalBuiltinIconId`. `legacyProtocolIconId` is deliberately separate:
historical wire/config value `codex` maps to ChatGPT artwork, without claiming
that the actual Codex product is ChatGPT or counting an additional brand.

To update artwork, obtain accurate original material, record its actual source
and terms, preserve the original, and prepare a transparent 256×256 RGBA PNG
using contain scaling into a centered 224×224 box. Preserve full shapes and
aspect ratio; use a renderer that retains SVG filters (the prepared images used
Chromium). Lossless PNG recompression must preserve decoded pixels. Recompute
hashes/dimensions/version, run generation, checks, decoding tests and browser
download verification. Updating a server-only entry does not require publishing
an App build. New display resources never authorize new remote commands.
