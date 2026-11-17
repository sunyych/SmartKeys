# Mobile Editions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. The available collaboration tools are used with Luna coder roles, as explicitly requested by the user; unavailable skill packages are not assumed to exist.

**Goal:** Deliver Android Bluetooth Lite and Desktop-controlled Android/iOS Regular with the approved landscape twelve-key interface.

**Architecture:** Shared models and control services remain reusable. Product entry points select transports, storage, and home widgets explicitly; native Android flavors give Lite a separate application ID. Desktop owns Regular actions, and saved custom layouts survive compact default migration.

**Tech Stack:** Flutter/Dart, Android Kotlin/Gradle, iOS Xcode, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-17-mobile-editions-design.md`

## Global Constraints

- Lite: Android only; direct Bluetooth HID; no Desktop discovery or launching.
- Regular: Android and iOS; Desktop-authoritative execution; landscape only.
- Regular geometry: four columns by three rows, twelve keys per page.
- Preserve user edits, original action IDs, and access to larger custom layouts.
- Main defaults to Regular. Do not modify the unrelated feature branch.
- Luna performs code changes; the primary agent coordinates, reviews, verifies, commits, and pushes.

## Task 1: Explicit edition routing and standalone Lite

**Owner:** Luna core.

**Files:** `lib/app_edition.dart`, `lib/app.dart`, `lib/main.dart`, `lib/main_lite.dart`, `lib/services/disabled_companion_service.dart`, `lib/data/profile_template_repository.dart`, `lib/data/config_repository.dart`, `lib/ui/home_screen.dart`, `lib/ui/settings_screen.dart`, a focused Lite shortcut settings screen, Lite profile assets, and corresponding tests.

**Interfaces:** Produces `AppEdition.regular`, `AppEdition.lite`, `buildEdition`, `SmartKeysApp({controller, edition = buildEdition, homeOverride})`, and `SmartKeysScope.editionOf(context)`. Consumes `const RegularHomeScreen({super.key})` from Task 2. The Lite Android entry point is `lib/main_lite.dart`.

- [x] Add regression coverage that explicitly builds each edition's real root; legacy component fixtures choose `homeOverride` explicitly.
- [x] Implement the edition selection contract:

```dart
enum AppEdition { regular, lite }
const buildEdition = String.fromEnvironment('LUMIAKEY_EDITION', defaultValue: 'regular') == 'lite'
    ? AppEdition.lite : AppEdition.regular;
```

- [x] Inject `IosCompanionHidService` with LAN companion for Regular on both mobile platforms. Inject `MethodChannelHidService` and a disabled, non-networking companion for Android Lite; reject Lite on unsupported platforms.
- [x] Load Lite's General, ChatGPT, and Chrome local profiles into separate storage; keep local edits and reuse the retained control surface and button editor.
- [x] Remove Lite's computer/app setup and Desktop settings. Provide the local shortcut settings entry. Remove Regular's phone-owned shortcut and orientation selection settings.
- [x] Run mobile analysis and focused Lite/root tests, then report changed files and any failures to the primary reviewer.

## Task 2: Regular navigation, launcher, keys, and touchpad

**Owner:** Luna interface.

**Files:** `lib/ui/regular_home_screen.dart`, `test/regular_home_screen_test.dart`, `test/regular_home_screenshot_test.dart`, and focused helper files if needed.

**Interfaces:** Produces `const RegularHomeScreen({super.key})`. Consumes `SmartKeysScope.of(context)`, `AppController.syncedApplications`, `desktopManifest.layoutById('keyboard')`, `layoutForApplication`, `launchRemoteApplication`, `executeRemoteButton`, existing pointer operations, `ComputerSwitcher`, `DesktopConnectionPanel`, `LocalDictationEntryButton`, and `SettingsScreen`.

- [x] Add widget tests for twelve-key geometry, launcher execution by Desktop application ID, General independent of foreground app, paging, disconnected actions, and computer-switch races.
- [x] Build the left scrollable navigation, central four-by-three grid, and persistent right pointer panel. Reuse existing connection and dictation components.
- [x] Await application activation before changing the selected shortcut surface; reject late completion after host/session or selection changes. Do not fall back to Bluetooth.
- [x] Render actual widget screenshots at 844 by 390 and 1180 by 820 logical pixels. Save launcher, General, ChatGPT, and iPad examples under `build/ui_screenshots/phone/` for primary visual review.
- [x] Run focused widget tests and analysis; report implementation and race-handling evidence to the reviewer.

## Task 3: Compact defaults and native build products

**Owner:** Luna platform.

**Files:** `packages/lumiakeys_protocol/lib/lumiakeys_protocol.dart` and compact-layout helper/tests, `desktop_companion/lib/desktop_controller.dart` and migration tests, Android Gradle/source-set manifests and MainActivity, `ios/Runner/Info.plist`, build scripts, `.github/workflows/release.yml`, `.github/workflows/ios-validation.yml`, and a dual-Android build workflow.

**Interfaces:** Android flavors `regular` and `lite`, with Lite's application ID suffixed `.lite`. Regular entry remains `lib/main.dart`; Lite entry is `lib/main_lite.dart`. Protocol action IDs remain stable.

- [x] Test that default layouts contain twelve selected actions and edited saved layouts survive migration.
- [x] Curate each built-in layout to twelve core actions and update only unmodified old defaults. Existing custom layouts remain complete.
- [x] Add Android flavor names and isolate Bluetooth permissions/hardware/native HID registration to Lite. Keep Regular's existing Android application identity.
- [x] Lock Regular orientation on native Android and both iPhone/iPad declarations; keep iOS full-screen support consistent with orientation locking.
- [x] Add reproducible edition build scripts. Update all affected release APK paths and Gradle test tasks after introducing flavors.

```powershell
flutter build apk --flavor regular -t lib/main.dart
flutter build apk --flavor lite -t lib/main_lite.dart
```

- [x] Ensure CI builds both Android products and the Regular unsigned iOS app, with downloadable build artifacts. Run relevant protocol/Desktop analysis and tests.

## Task 4: Integration review, validation, and delivery

**Owner:** Primary agent, with fixes delegated to the appropriate Luna coder.

- [x] Review edition routing without test-only implicit behavior, stale input cancellation, old-configuration preservation, and all platform/release changes.
- [x] Run the complete appropriate mobile/protocol/Desktop tests and analyze after integration. Resolve actual regressions; distinguish stale legacy UI assertions from product defects.
- [x] Inspect rendered screenshots and request layout corrections when needed.
- [x] Build both Android flavors, record artifact sizes and hashes, and copy clearly named APKs into `build/artifacts/1.4.0/` if builds succeed. Do not commit generated artifacts.
- [x] Commit and push main, then check the resulting Android/iOS CI builds until a terminal result. Keep the two editions reproducible from their dedicated entry points and Android flavors in the shared main branch.
- [x] Deliver concise Chinese release notes, installable Android artifacts, branch/commit references, and precise iOS compilation/signing/device-validation limits.
