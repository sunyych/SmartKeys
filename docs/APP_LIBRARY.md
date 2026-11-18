# App library

An App entry contains its icon and supported shortcut libraries. macOS uses one
variant; Windows and Linux share a variant only for supported systems. An App can
be Windows-only within that family. Safari, Finder and Sketch expose only macOS.
The context label distinguishes a native application, website, or terminal.

Each library contains up to twelve actions. Assigned actions show their keyboard
combination. A **Requires configuration** action has no default binding and sends
no input until configured. Defaults refer to the linked official documentation
and a US keyboard layout; application preferences can override them.

## Full and Desktop

Open **App library** on LumiaKey Desktop, find an App, and preview its OS variant.
Installation uses the current computer's OS. **Add a new copy** keeps existing
profiles intact. An explicit replacement updates unchanged defaults and retains
user edits and additional actions. Library profiles appear on the paired Full
phone with their associated App icon.

Download a `.lumia-app.json` bundle from the online App library and use
**Import reviewed App bundle** on Desktop. The bundle includes the App record,
its supported variants and the matching PNG. Registered artwork hashes, package
size, available OS and keyboard-only actions are checked before installation.
Online-only icons are carried with the profile so the phone can display them
without a configured icon server. The current importer accepts publications
matching the catalog shipped with the client; changing that catalog requires a
client update.

For Apps already managed by Desktop, foreground protections still apply. Other
library profiles are manual keyboard profiles: focus the intended App on the
computer before pressing its keys. Installing a profile does not turn an
OS-discovered launch-only App into a managed input target. Full's phone library
provides previews and directs installation to Desktop.

## Bluetooth Lite

Open the local App library, choose the controlled computer OS, preview the
shortcuts, and install a local profile. The phone's Android OS does not determine
the target computer OS. Only the fifty bundled Apps are offered offline; no
network access is added. Imported profiles keep their source App and OS identity.

Private Launchpad combinations remain separate. Configure and save a Bluetooth
launch combination on the phone, and configure the matching launch hotkey on the
computer. Importing an App library never creates or replaces that combination.
Opening a local profile changes the displayed shortcuts without launching an App.

## Online platform and compatibility

The community service publishes an App catalog and immutable App bundles under
`/v1/apps/`. The web App library supports search, OS filtering, action previews,
source links and complete bundle downloads. Existing `/v1/icons/` endpoints
remain compatible. Publications are reviewed source assets; no public submission
or moderation interface is introduced.

Public library actions contain a single keyboard chord or an explicit unassigned
action. They cannot contain native launch commands, shell commands, executable
paths, macros, voice or KVM actions. Downloading, previewing and installing a
bundle never executes its shortcuts.

The existing `codex` artwork alias remains a legacy display compatibility rule.
It does not identify Codex as ChatGPT or install ChatGPT shortcuts for Codex.

See `packages/app_library/catalog.json` for the canonical registry and official
shortcut sources, and `scripts/generate_app_library.py --check` for reproducible
client/server mirrors. Lite's generated mirror is contained in its standalone
source export.
