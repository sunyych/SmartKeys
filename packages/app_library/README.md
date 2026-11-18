# App icons and shortcut libraries

`catalog.json` is the reviewed App-library registry. Each record references its
exact canonical ID in `../app_icon_catalog/catalog.json`; image originals,
provenance and PNG hashes remain owned by that package. Ordinary product aliases
are shared. The historical artwork-only `codex -> chatgpt` mapping is deliberately
excluded from App lookup and shortcut-library installation.

Each App has up to two library families: `macos` and `windowsLinux`. Explicit
`supportedOS` controls availability; the latter family does **not** imply Linux
support. `context` identifies native, web, or terminal use. Coverage is deliberately
conservative: a missing OS means this catalog does not provide that product/context
library, rather than claiming every possible product edition is unavailable.
Safari, Finder and Sketch are macOS only; Windows shell utilities remain Windows
only. GitHub Desktop's official support is macOS and Windows, not Linux.

The initial publication supplies verified single-chord defaults for common Apps,
with official sources recorded on each library. Other named actions explicitly
have `keys: []` and `requiresConfiguration: true`; these are configuration templates,
**not working default shortcuts**. Sources may describe customizable commands or
product availability without specifying default keys. No binding is inferred
merely by replacing Ctrl with Command. For example, Chrome history/tab navigation
uses its separate system tables, and VS Code's differing Linux formatting default
is replaced by a documented cross-system Quick Fix action. Meeting controls and
recording remain subject to the host application's focus and permissions.

Public actions allow only normalized modifiers plus one named key, or explicit
unassigned actions. Commands, paths, executable identities, macros, voice and KVM
actions are rejected. Named punctuation is converted by a target adapter: Desktop
uses `canonicalKeyToLiteral`; Lite maps `EQUAL/QUOTE/BACKTICK` to Android HID's
`EQUALS/APOSTROPHE/GRAVE`. The library does not grant native execution authority.

Generate and check from the repository root:

```sh
python scripts/generate_app_library.py
python scripts/generate_app_library.py --check
python -m unittest scripts/test_generate_app_library.py
```

`model.dart.template` produces identical, self-contained Dart models in Full,
Desktop and independent Lite, and a self-contained server JSON registry. The
generator performs no network access. Full-only source exports omit Lite and use
`--check --full-only`. The checked publication requires exactly the canonical icon
cohort with matching aliases and bundled flags; runtime parsers can accept a
bounded subset. Runtime optional `context` and catalog `version` default only
when absent, never when explicitly null. Collections are deeply immutable.

The generated `registeredAppIconHashes` contains all sixty registered hashes.
`registeredAppActionHashes` hashes each original action's sorted-key, compact,
UTF-8 JSON with SHA-256; source hashes identify imported baselines, not permissions.
When publishing a changed library, increment its version and catalog version,
regenerate all mirrors and run catalog/model/service/browser acceptance checks.
Retain official provenance, and leave undocumented defaults unassigned.

## Bluetooth Lite

Local settings → **App library** browses the fifty bundled Apps without networking.
Choose the controlled computer OS explicitly; Bluetooth does not reveal it.
Preview the source, context and assigned count before **Install icon + shortcuts**.
Installation always adds a new local profile, storing icon association, keys and
source metadata together in the existing atomic profile write. It preserves
older profiles, fifteen-key pages, and every private Launchpad combination.
Failed persistence publishes neither the icon association nor the new keys.

Unassigned tiles send no HID and open local configuration. Set their actual
combination in the profile editor before use. Existing keyboard and media
shortcuts remain supported. Imported libraries never configure app-launch keys;
those still require the user's private, explicitly saved computer shortcut.
