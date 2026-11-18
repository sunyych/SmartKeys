# Installed Launchpad and header implementation plan

> **For agentic workers:** Execute through the assigned Luna subagents with root
> review between independently testable tasks. Use checkbox steps to track work.

**Goal:** Apply the requested Full header/branding and configure twelve Launchpad
slots from the computer's complete installed/explicitly added application catalog.

**Architecture:** Desktop-local launch-target registry, opaque stable wire IDs,
separate launch-only capability, and a shared Full top bar. Existing managed
shortcut and foreground protections remain separate.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12.2, existing shared protocol, Windows
registration/Shell APIs, macOS NSWorkspace and Linux GIO.

**Spec:** `docs/superpowers/specs/2026-11-17-installed-launchpad-and-header-design.md`

## Global constraints

- Full/Desktop `1.7.0+9`; independent Lite unchanged at `1.1.0+2`.
- Keep twelve slots and landscape-only Full controls; retain touchpad/pairing.
- Actual launch locations and arguments stay on Desktop, never in phone payloads.
- Dynamic launch-only apps never gain managed key/voice/foreground permissions.
- Only root commits, pushes, merges and installs; use current validated source.

### Task 1: Shared header and Full dynamic-app presentation — Luna interface

**Files:** `lib/ui/regular_home_screen.dart`, `pubspec.yaml`,
`lib/controllers/app_controller.dart`, `lib/services/companion_service.dart`,
corresponding Full regression/screenshot tests.

**Interfaces:** consumes protocol `RemoteApplication.launchOnly` and dynamic-ID
validation; uses existing media IDs and `CompanionIconConnection`.

- [ ] Cover top-bar geometry/brand position, long host names and large font in
  844×390 and tablet layouts; preserve twelve-key, touchpad and session tests.
- [ ] Move controls and reuse the single real brand asset; reserve dictation
  space so Settings receives taps.
- [ ] Cover actual SmartKeysApp → Settings → icon library → search → back route.
- [ ] Keep dynamic apps off shortcut sidebar, launch without managed confirmation,
  and accept only selected valid dynamic icon IDs through existing session caches.
- [ ] Run focused tests/analysis, capture current screens, hand off for review.

### Task 2: Registry, discovery and Desktop chooser — Luna core

**Files:** new `desktop_companion/lib/installed_app_registry.dart`,
`installed_app_discovery.dart`; `desktop_controller.dart`, `desktop_ui.dart`,
Desktop pubspec and focused tests.

**Interfaces:** publishes the six-kind local `InstalledLaunchTarget` and
`InstalledAppRegistry.resolve(String)` contract in the spec; consumes platform
launch/icon resolvers and optional launch-only protocol metadata.

- [ ] Publish the shared types first and coordinate native provider signatures.
- [ ] Test stable identities, duplicate labels, large catalogs, manual persistence
  failures, removal/reinstall and failed/partial scans.
- [ ] Implement bounded OS discovery/cache and local file-picker registration;
  separate catalog refresh from three-second runtime checks.
- [ ] Add searchable/virtualized chooser with refresh/manual-add and unavailable
  states; preserve atomic slot/config persistence.
- [ ] Route dynamic launches and icon reads only through selected live registry
  targets; close raw remote legacy launch bypasses without changing trusted
  locally configured actions or existing managed shortcut safety.
- [ ] Run Desktop tests/analysis and capture chooser states for root review.

### Task 3: Native launch, icons and protocol — Luna platform

**Files:** `desktop_actions.dart`, new `installed_app_launcher.dart`,
`app_icon_service.dart`, required native platform adapters/CMake,
`companion_server.dart`, shared protocol and corresponding tests.

**Interfaces:** consumes registry resolver; produces strict launch-only wire
projection, installed-ID validation and registered native launch/icon operations.

- [ ] Test rejection of unknown/stale/wrong-platform IDs and raw path/args/type
  payloads, with zero OS execution; preserve existing managed tests.
- [ ] Implement launchOnly metadata, empty layout, selected-only sync and no local
  locators on the wire, plus compatible capability advertisement.
- [ ] Implement fixed-argument/native launches for each target kind, deferring
  Linux desktop-entry semantics to GIO; do not fake activation confirmation.
- [ ] Extend native icons through registry authorization and existing PNG bounds.
- [ ] Run protocol/native/action/icon tests and analysis; hand off for review.

### Task 4: Integrate and deliver — root

- [ ] Review authorization, persistence, performance and UI geometry; return fixes
  to owners and run the complete affected test suites.
- [ ] Commit/push the development branch and run artifact-only multi-platform CI.
- [ ] Build signed-with-existing-development-key Android and Windows delivery,
  inspect actual versions/assets, then install to already authorized devices.
- [ ] Fetch/merge latest main safely, push main after checks and publish package,
  source, screenshot and checksum links with exact verification scope.
