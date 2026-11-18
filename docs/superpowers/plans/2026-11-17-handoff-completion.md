# Launcher, icons, and independent Bluetooth handoff completion

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. This environment uses the available collaboration tools and Luna coder roles requested by the user.

**Goal:** Integrate the uploaded WIP with the delivered 1.4.0 functionality and complete independently buildable Bluetooth Lite, Desktop-configured mobile Launchpad, icon delivery, Linux X11 support, safe exports, and current screenshot evidence.

**Architecture:** Preserve the validated main implementation and integrate WIP commit `08993e6` on `feature/mobile-launcher-and-editions`. The Full mobile entry remains `RegularHomeScreen`; independent Lite lives entirely in `apps/bluetooth`. Desktop manifests own twelve launcher slots and action configuration; authenticated native icons and the registered central icon catalog are optional resources whose failure cannot block input.

**Tech Stack:** Flutter 3.44.2 / Dart 3.12.2, Android Kotlin/Gradle, Windows/macOS/Linux Desktop, Rust/Axum, existing dashboard, artifact-only GitHub Actions.

**Spec:** `docs/handoffs/2026-11-17-mobile-launcher-and-editions.md` and `docs/handoffs/2026-11-17-wip-snapshot.md`, with the direct user decisions below taking precedence.

## Global constraints and confirmed decisions

- The user selected reuse of uploaded WIP source, rather than rebuilding it from scratch.
- Preserve **twelve keys and landscape-only use**. The older handoff's eight-slot/portrait wording does not override this direct clarification.
- Migrate saved eight-slot launcher lists to twelve slots without deleting existing assignments. An explicitly saved empty configuration must remain empty after restart.
- Preserve the delivered 1.4.0 shortcuts, touchpad, fixed media controls, custom layouts, and input/session protections.
- Full remains Flutter, Android/iOS mobile and Windows/macOS/Linux Desktop. Linux input is X11-dependent; unsupported Wayland operations must be explicit.
- Bluetooth Lite is Android-only with its own dependencies and native project. No network/microphone permissions, recording/ASR, cloud accounts, Desktop service, or online dashboard.
- Reuse the WIP independent package ID `com.lumiaiq.bluetoothlite`; it does not silently replace the installed legacy flavor package.
- Do not create remote repositories, publish tags/releases, or modify release-publishing workflows for this task. Validate and deliver build artifacts on the feature branch; do not overwrite main.
- Preserve all existing work. Resolve the three integration conflicts deliberately; do not reset or clean the repository.
- Run one Flutter test process per project at a time. Each changed interface needs current screenshot coverage and one combined index; do not inspect every image individually.

## Task 1: Independent Bluetooth product and safe source exports

**Owner:** Luna core.

**Files:** `apps/bluetooth/**`, `scripts/build_lite.ps1`, `scripts/build-bluetooth-lite.sh`, `scripts/build-full.sh`, `scripts/export-editions.sh`, a standard-library export implementation, `analysis_options.yaml`, `.github/workflows/bluetooth-lite.yml`, edition documentation.

**Consumes:** Existing native HID encoders/controller behavior and local General/ChatGPT/Chrome shortcut definitions. No parent-project imports or dependencies are permitted.

**Produces:** Independently buildable Android app, accurate isolation checks, safe fresh-directory Full/Lite exports, current Lite screenshots.

- [x] Fix Gradle build directories so Flutter finds the APK in the independent project's expected `build/app/outputs/flutter-apk/` location.
- [x] Supply local profiles, editing and persistence, touchpad/mouse/media controls, save-failure feedback, modifier-only handling, and held-input release on background/context changes.
- [x] Test independent Shift (no extra character), successful and failed saves, restart persistence, lifecycle release, and local control interactions.
- [x] Verify the resolved dependency graph, plugin registration, source sets, and actual release/debug manifests: no Full/cloud/recording/network dependencies or permissions.
- [x] Implement fresh-destination/staging exports with no overwrite, unsafe symlinks, Git data, signing keys, build output, local configuration, or parent-repository dependencies.
- [x] Resolve dependencies, analyze, test, and build the exported Lite outside the repository. Validate the Full export excludes the independent Lite project.

## Task 2: Full mobile, shared manifest, and icons

**Owner:** Luna interface.

**Files:** Protocol models/tests, `lib/ui/home_screen.dart` merge conflict, `lib/ui/regular_home_screen.dart`, controller/companion/image-store/icon client files, Full pubspec, corresponding root tests and screenshots.

**Consumes:** Desktop-published launcher assignments and authenticated `GET /icons/{appId}` resources. Native icons must be PNG, at most 64 KiB and 512 by 512 pixels. Central catalog formats are explicitly coordinated with Task 3.

**Produces:** `launcherSlotCount = 12`, optional compatible `launcherApplicationIds` with configuration-presence semantics, Desktop-owned twelve-slot Launchpad, per-computer persistent icon caching, and genuine Full-root regression coverage.

- [x] Resolve the Home and protocol conflicts, retaining main's compact defaults and legacy component contracts while putting the product Launcher in `RegularHomeScreen`.
- [x] Publish/consume twelve slots, pad old eight-slot lists, validate references, hide synchronized application/slot data when Apps Sync is off, and distinguish absent configuration from intentionally cleared slots.
- [x] Preserve default Launcher entry, explicit return, clock/media controls, disconnected/unconfigured CTAs, fixed landscape, and persistent touchpad. Never edit launcher bindings on the phone.
- [x] Require the correct computer and a fresh application activation acknowledgement before enabling app shortcuts. Ignore stale activation notifications after returning home or switching computers.
- [x] Complete original-icon request, authenticated download, bounded PNG validation, per-computer cache and artwork fallback. Honor Sync Icons in both requests and rendering; late responses cannot cross computer sessions.
- [x] Test startup, no configuration, offline/disconnect, activation failure, stale notifications, return home, host switching, cache invalidation, invalid/oversized icons, and disabled synchronization.
- [x] Keep valid existing regressions and generate current Full phone/tablet screenshots without individual image review.

## Task 3: Desktop, central icon service, and Linux

**Owner:** Luna platform.

**Files:** Desktop controllers/UI/actions/native icon service/server/platform runners/tests, `community_server/**`, `.github/workflows/linux-validation.yml`, icon provenance documentation and registered assets.

**Consumes:** Task 2's shared twelve-slot and presence contract. Desktop remains authoritative for executable paths and shortcuts.

**Produces:** Atomic launcher configuration and manifest revision updates, authenticated bounded native icon endpoint, complete registered icon catalog in the existing dashboard, honest Linux capabilities and artifact build checks.

- [x] Resolve `desktop_actions.dart` while retaining both WIP icons/Linux work and main's General media behavior.
- [x] Make the manifest the atomic source of launcher assignments and revision. Handle save failures, restart, old eight-slot migration, and explicitly cleared settings.
- [x] Validate/cancel/time-limit native icon extraction on supported platforms. Enforce authentication, Sync Icons gating, known application IDs, size/type/dimensions, and ETag behavior at the companion endpoint.
- [x] Register actual distinct artwork for every supported brand; document canonical IDs, compatibility aliases, original provenance, license uncertainty and trademark guidance accurately. Do not count aliases as additional artwork.
- [x] Extend the existing Rust dashboard with search, catalog/download, offline/error/unknown states, strict registered sources, and bounded downloads. Keep the Docker image self-contained and preview mode independent of PostgreSQL.
- [x] Support Linux X11 keyboard/pointer/media/fixed tools only where the required backend exists; do not announce unavailable pointer capability or call an unimplemented native channel. Fix locale-dependent parsing and CI native dependencies.
- [x] Run protocol/Desktop/Rust tests, native platform builds through artifact CI, browser behavior/overflow checks, and current web/Desktop screenshots for the combined index.

## Task 4: Integration and delivery

**Owner:** Primary agent; fixes stay with their Luna owners.

- [x] Review conflict resolutions and capability/product boundaries against the handoff and direct user decisions.
- [x] Run appropriate complete analysis and tests for Full mobile, protocol, Desktop, independent Lite, and Rust; distinguish optional database/native-model skips from passing tests.
- [x] Verify standalone exported builds and actual APK dependency/permission isolation.
- [x] Build final Android and Desktop artifacts; use artifact-only hosted checks for iOS/macOS/Linux/Windows and wait for terminal results.
- [x] Generate one current screenshot index for mobile, Desktop, Lite and web, without mixing prior delivery images or inspecting each image individually.
- [x] Update the handoff with verified completion, residual platform/device limits, and reproducible commands.
- [x] Review the final diff, commit and push the feature branch, and deliver artifact links with accurate installability/signing limits. Do not publish tags/releases or overwrite main.
