# Full header and installed-application Launchpad

The user explicitly requested these changes after the 1.6 delivery: move the
host, clock, play/pause and mute controls beside the workspace title at the top;
put the LumiaKey wordmark below the real LumiaKey icon at the top of the rail;
and let Desktop configure Launchpad with all installed applications.

Full and Desktop become **1.7.0+9**. Standalone Lite remains **1.1.0+2**.
Work is isolated on `codex/launcher-all-apps-and-header`, then committed,
pushed and merged into main after verification, following the user's standing
instructions. Existing installation authorization remains applicable.

## Interface

Use one shared top bar: current workspace title at left, host/HH:mm:ss and the
existing media buttons centrally, connection/computer switching/dictation/settings
at right. Long names truncate with accessible full labels. The content below
retains twelve keys, landscape-only use and the right touchpad. The rail starts
with `assets/app_icon/app_icon_source.png`, then LumiaKey; remove the bottom
wordmark. Existing shortcut IDs, media guards, pairing, dictation consent and
per-computer/session icon caching stay intact. The dictation overlay must not
cover Settings. Test navigation through the actual app's Settings route.

## Desktop-owned application registry

Add `installed_app_registry.dart` and `installed_app_discovery.dart`. The
registry owns local launch targets and manual-target persistence. Operating-system
scan results are reconstructible; full scans occur at startup, explicit refresh
and a bounded cache interval, not on every three-second runtime poll.

The shared contract is `InstalledAppRegistry.entries`, `resolve(id)`, `refresh`,
`addManual` and `removeManual`; `resolve` returns only available local targets.
`InstalledLaunchTarget` contains `id`, `name`, `kind`, `identity`, `locator`,
optional `executablePath`/`startupWMClass`, and `available`/`manual` flags.
Kinds are `windowsAppId`, `windowsShortcut`, `windowsExecutable`, `macBundle`,
`linuxDesktopEntry`, and `linuxExecutable`. IDs use
`installed.<first 32 SHA256 hex of kind.name + NUL + identity>`; the kind includes
the owning platform and target type.

- Windows: retain Name/AppID from Start applications; supplement Start Menu
  shortcuts and registered App Paths. Do not infer executable apps from uninstall
  display names. Launch registered AppIDs, shortcuts and executable files through
  fixed native APIs/arguments.
- macOS: discover actual bundles, including system/user Applications and registered
  locations, stopping traversal at bundle boundaries. Launch exact bundle URLs;
  do not resolve arbitrary applications by a fuzzy display name.
- Linux: use GIO application registration/desktop-entry semantics, including XDG
  overrides, visibility and availability. Let the OS handle Exec field codes,
  Terminal, DBus and packaging wrappers. Never parse Exec into a shell command.

A searchable Desktop chooser lists installed launchable applications and
supports refresh and explicit local file picking for portable/unindexed apps.
Manual targets survive restart; failed saving must not claim success. Preserve
slot assignments when a target disappears and show it unavailable.

## Wire and execution boundaries

Add optional `RemoteApplication.launchOnly`, default false, plus an empty shared
`installed.launch-only` layout and `installed-launcher-v1` server capability.
Send only selected launcher dynamic applications to the phone, with an opaque
executable reference; never send registry locators, local arguments or paths.
Dynamic applications do not create sidebar shortcut categories. Their launch
success means the OS accepted a registered launch, not a fabricated foreground
confirmation. Keep the phone on Launchpad after starting them.

Both native launching and icon extraction resolve dynamic IDs through the local
registry. Phone-supplied executable/path/argument fields are rejected. Strictly
validate dynamic IDs, field types and duplicate application IDs. Close the old
raw legacy launch route by resolving only registered/configured IDs at the
controller boundary; trusted Desktop-configured action targets remain local.
Do not enlarge managed shortcut/foreground/voice privileges. Unknown, stale,
unregistered or wrong-platform targets fail without an OS launch call.

Native icons retain the existing size/format, authentication and sync gates.
Full's controller and companion icon connection must accept validated selected
dynamic IDs while preserving per-computer/session isolation and bounded caches.

## Ownership and verification

Luna core owns registry/discovery/controller/Desktop chooser and Desktop version;
Luna platform owns native actions/icons/protocol/server routing and platform
adapters; Luna interface owns Full layout, brand asset registration, launch-only
rendering and Full icon transport. Root owns review, Git, builds and delivery.

Tests cover hundreds of apps, duplicate names, stable IDs, restart, manual-save
failure, uninstall/reinstall, partial scans, selected-only sync without paths,
unknown/stale/hostile requests, fixed launch arguments, original managed guards,
native icon gates and actual Settings-to-gallery routing. Capture current UI
states under `build/handoff-1.7.0/screenshots` without individually inspecting
images. Run focused tests then relevant complete mobile/Desktop/protocol suites,
analysis, native checks and Android/Windows/Apple/Linux builds. Physical checks
use safe navigation or a deliberately chosen harmless test target; never send
user input or accept diagnostic sharing during verification.
