# Tablet shortcut board implementation plan

> For agentic workers: implement the scoped tasks with Luna subagents. Root
> reviews interfaces and results and owns commit/push from the shared checkout.

**Goal:** Ship a full-screen tablet shortcut board and a usable iPad client
connection path without regressing the Android phone controls or dictation.

**Architecture:** Reuse profile/button models and Desktop action execution.
Window constraints select an independent keyboard-only presentation. iPad uses
authenticated unicast Desktop pairing instead of Android Bluetooth HID.

**Tech stack:** Flutter/Dart, existing native Android HID and Desktop adapters,
Swift iOS runner, PowerShell validation, existing local ASR package.

**Spec:** `docs/superpowers/specs/2026-10-20-tablet-control-board-design.md`.

## Global constraints and shared interfaces

- Preserve `controlButtonCount == 15`; add `maxControlButtonCount == 60`.
- Add `enum ControlSurfaceLayout { automatic, phone, shortcutBoard }`.
- `AppPreferences.controlSurfaceLayout` defaults to `automatic`.
- `AppPreferences.tabletKeysPerPage` defaults to `40`; every integer 24..60 is
  valid. Keep 24/40/60 presets and support values such as 32, 48 and 59.
- Controller APIs:
  `Future<void> updateControlSurfaceLayout(ControlSurfaceLayout value)` and
  `Future<void> updateTabletKeysPerPage(int value)`.
- Existing local profiles remain 15 entries until additional slots are edited.
  Valid local positions are 0..59. Phone banks contain at most 15 entries.
- `AppController.updateButton` may fill missing positions through the edited
  position, bounded at 60. Import/export must preserve additional positions.
- Existing input transport and profile/button IDs remain authoritative.
- iOS-only transport selection goes in `lib/app.dart`, owned by connection
  worker. Home is owned by layout worker; Settings by configuration worker.
- New manual-pairing widget is standalone; configuration worker embeds it in
  Settings. Use an optional interface to avoid breaking existing test fakes:
  `ManualCompanionConnection.connectManually(String code)` and `disconnect()`.
- Both Flutter packages use version `1.3.0+5`.
- No generated images, HTML, installers, credentials or coverage are committed.

## Task 1: Configuration and profile compatibility

**Owner:** Luna configuration worker.

**Files:** `lib/models/config.dart`, `lib/controllers/app_controller.dart`,
`lib/data/config_repository.dart`, `lib/data/profile_transfer_service.dart`,
`lib/ui/settings_screen.dart`, `lib/ui/button_editor_screen.dart`, and related
configuration/controller/import tests. New tests may be separate files.

- [x] Add failing tests for legacy 15-key decoding, a button at position 59
  surviving JSON import/export, invalid positions and preference round trips.
- [x] Add preference fields and enum with tolerant legacy defaults, preserving
  unrelated preferences and profile data. Bound accepted slots at 60.
- [x] Extend safe editing and swapping to unused board positions.
- [x] Add Settings controls for presentation and keys per bank; embed the
  connection worker's standalone manual-pairing widget.
- [x] Run the owned focused tests and Dart formatting; report exact files and
  any interface deviations. Do not commit from a worker.

Configuration task validation from the NTFS checkout: `tablet_config_test.dart`,
`app_controller_test.dart`, and `config_repository_test.dart` passed (39 tests).
The app and Desktop package versions are updated. This records Task 1 only; the
full delivery validation is recorded below. Native iOS unsigned compilation and
plugin linkage passed in [Mac CI run 39519873752](https://github.com/sunyych/SmartKeys/actions/runs/39519873752);
signing and physical iPad acceptance remain unverified.

Example acceptance assertions:

```dart
expect(AppPreferences.fromJson({}).tabletKeysPerPage, 40);
expect(AppPreferences.fromJson({}).controlSurfaceLayout,
    ControlSurfaceLayout.automatic);
expect(ProfileConfig.fromJson(profile.toJson()).buttons.last.position, 59);
```

## Task 2: Responsive board and interaction

**Owner:** Luna layout worker.

**Files:** `lib/ui/home_screen.dart`, new focused board/layout widgets under
`lib/ui/`, `test/tablet_control_board_test.dart`, root screenshot suite/support.

- [x] Add tests showing automatic tablet selection at 600px shortest-side,
  compact phone layout on 915x412, explicit override and split-window fallback.
- [x] Render 24..60 shortcut slots in fit-to-screen portrait/landscape grids,
  retaining label/icon/editor behavior. Use existing local/remote execution.
- [x] Add bank controls for all local/remote keys, clamp/reset bank when context
  changes, and release held input before changing banks or dimensions.
- [x] Keep the existing home header and dictation owner in place; no wheel or
  mouse region in board mode. Test actual taps and editing an unused slot.
- [x] Add screenshot cases for 768x1024, 1024x768, 1366x1024, split width and
  increased text size, including the listening chip. Assert no overflow.
- [x] Run focused tests from the NTFS stage and report screenshot metadata.

## Task 3: iPad runner and explicit Desktop connection

**Owner:** Luna iPad/connection worker.

**Files:** new `ios/` runner; `lib/app.dart`; new platform/connection widgets and
services; `lib/services/companion_service.dart`; Desktop server/UI/tests;
optional iOS validation workflow and setup documentation.

- [x] Test manual-code validation, token header authentication, host/manifest
  readiness, unicast heartbeat expiry and stale-response host replacement.
- [x] Add authenticated server information and Desktop connection-code UI,
  using only local IPv4 addresses and no token in screenshots or diagnostics.
- [x] Implement optional manual connection interface and a standalone pairing
  widget for Settings; disable iOS broadcast discovery by default.
- [x] Add an iOS LAN shortcut adapter mapping only supported keyboard chords
  to atomic existing Desktop shortcuts. Reject unsupported actions visibly;
  never label this transport Bluetooth HID or allow HID text batches.
- [x] Generate a dedicated iOS runner without overwriting existing application
  files. Configure name/identity, permissions, orientations, power channel and
  platform input selection. Do not introduce unneeded package dependencies.
- [x] Add a Mac-side unsigned build validation path and document local signing
  and real-iPad acceptance steps. Report Windows-only evidence separately.
- [x] Run focused Dart/HTTP tests and formatting. Root reviews Swift source;
  do not claim a native build from this Windows host.

## Task 4: Root integration and delivery

- [x] Review the final code against the spec; request Luna fixes for concrete
  defects and refresh all tested-source hashes against the NTFS stage.
- [x] Update both app versions to 1.3.0+5; run four package analyses, full tests,
  Dart LCOV, Kotlin and installer checks appropriate to the final changes.
- [x] Generate the ignored offline HTML screenshot index and ZIP.
- [x] Visually inspect tablet layouts and phone regression captures.
- [x] Build Android/Windows, install on connected supported devices and this
  PC, and preserve local models/preferences. An iPad build/install requires
  Mac/Xcode/signing and a connected iPad; report any absent prerequisite.
- [x] Commit only intended source/test/docs changes on existing main; push and
  verify remote SHA equality. Return artifacts, validation and limits.
