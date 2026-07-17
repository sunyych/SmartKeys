# SmartKeys

SmartKeys is a responsive Flutter control surface for a phone acting as a
Bluetooth HID keyboard/controller. It is an Android-only app and requires
Android 9 (API 28) or later. Version 1 keeps the computer side at zero install:
profiles are selected manually on the phone and the app does **not** claim to
detect the foreground desktop application.

## Implemented V1.1 supplement

- Portrait uses one shared 15-button state in a 3 × 5 grid.
- Landscape left/right uses the same state in a 5 × 3 grid, with buttons and
  the profile navigation control arranged in a 2:1 split.
- Rotation clears held-button state, cancels active wheel/mouse input, and
  invokes `releaseAllKeys()` without recreating the Profile or connection
  controller.
- SmartKeys starts in Landscape by default. Portrait and Auto remain available
  only through Screen Orientation in Settings, and the choice persists.
- Configuration schema v6 owns an ordered list of independent Profiles, each
  with 15 buttons, navigation actions, icon, optional target application,
  accent color, and timestamps.
- Cross-platform shortcuts use `PRIMARY`: Automatic mode maps it to Command on
  Apple hosts and Ctrl on Windows/Linux hosts, with an explicit manual override
  in Settings when a Bluetooth computer name is ambiguous.
- The General default matches `docs/screenshots/default_general_layout.png`;
  the final mouse-pad result is in `docs/screenshots/final_mouse_layout.png`:
  mute/volume/undo/redo, media/open/favorite, then cut/copy/paste/close/delete.
- General uses a four-way mouse direction pad on the right. Holding a direction
  emits repeated relative mouse movement every 40 ms; releasing it immediately
  sends a neutral mouse report. Other profiles can retain a Jog Wheel.
- Edit mode keeps tap-to-configure and adds long-press drag-and-drop: dropping
  one button on another swaps their complete configurations and persists the
  new order.
- The free edition starts with exactly four JSON-backed slots: General, Web,
  Zoom / Teams (Windows), and Custom. Photoshop and SolidWorks are retired.
- Tapping the Profile name opens the dropdown; swiping it left or right switches
  to the next or previous Profile without opening the dropdown.
- Profiles can be created, copied, edited, reordered, deleted, selected as the
  default, imported/exported, and restored from built-in templates. The free
  limit is four; a JSON or community pack can replace any occupied slot.
- Shortcut Community provides curated offline packs plus clipboard/file JSON
  exchange: paste or import a Profile, copy the active Profile JSON, or export
  it as a `.smartkeys.json` file for sharing.
- Buttons support text, stable semantic built-in icon IDs, or a PNG/JPEG/WebP
  copied into the app-private directory. Image fit, scale, position, overlay
  labels, colors, action, and feedback are editable.
- The offline icon catalog covers common editing, navigation, media, design,
  image, CAD, and 3D actions. It includes search, category filtering, recent
  choices, favorites, live preview, size, color, and clear controls.
- Missing private images render an explicit placeholder. Unreferenced private
  images are cleaned after confirmed configuration changes or Profile deletion.
- Android registers the phone through the public Bluetooth HID Device profile,
  lists already paired hosts, connects/disconnects the selected computer, and
  sends keyboard, consumer-control, mouse movement, and mouse-wheel reports.
- Platform launcher icons are generated from
  `assets/app_icon/app_icon_source.png`. Android 8+ uses a deep-blue adaptive
  background with the transparent safe-zone foreground in
  `assets/app_icon/adaptive_foreground_source.png`.

## Architecture

The responsive UI reads one `AppController`; portrait and landscape are only
layout projections. Persistent data lives in `AppConfig` schema v6, templates
live under `assets/profiles/`, community packs under `assets/community/`, and
external effects are behind services:

- `ConfigRepository`: JSON persistence plus schema v1-v5 migration, including
  the four-slot free-edition transition.
- `HidService`: Android access/pair/connect lifecycle plus key
  press/release/step and connection state.
- `OrientationService`: applies Auto/Portrait/Landscape platform policy.
- `PrivateImageStore`: imports, thumbnails, resolves, and cleans private media.

The Android native HID boundary uses the `smart_keys/hid` method channel:

- Dart → native: status/snapshot queries, permission and discoverability
  requests, paired-host refresh, connect/disconnect, key press/release/step,
  and release-all.
- Native → Dart: complete connection snapshots covering permission required,
  Bluetooth off, registration, disconnected, connecting, and connected states.
- Native reports: keyboard report ID 1, consumer-control report ID 2, and
  relative mouse X/Y/wheel report ID 3. Held keyboard usages and modifiers are
  reference counted so overlapping shortcuts release safely.

On Android 12 and later the app asks for Nearby devices access. It never scans
for arbitrary peripherals; connection choices come from Android's already
paired devices. The target computer needs no SmartKeys companion app.

## Pair and connect

1. Open SmartKeys and tap the Bluetooth status chip, or open Settings →
   **Computer connection**.
2. Grant Nearby devices access if Android asks.
3. Tap **Make phone discoverable**.
4. On Windows, open **Add Bluetooth device**; on macOS, open Bluetooth
   Settings. Pair the phone from the computer.
5. Return to SmartKeys, tap **Refresh**, and connect the paired computer.

Pairing is managed by Android/Windows. SmartKeys retains no separate pairing
secret and exposes explicit permission, Bluetooth-off, registration, connection,
and native error states in the connection sheet.

## Run and verify

```sh
flutter pub get
flutter run                 # Android device only
flutter analyze
flutter test
(cd android && ./gradlew :app:testDebugUnitTest)
flutter build apk --debug
```

Automated coverage includes portrait/landscape grids, landscape ratio, held-key
rotation safety, held mouse movement/release, edit-mode drag reordering,
tap/dropdown and swipe Profile switching, the four-slot limit and replacement,
community pack installation, JSON validation, template loading,
built-in/custom/missing-image rendering, orientation persistence, schema
v1/v2/v3/v4/v5 → v6 migration, automatic Command/Ctrl resolution,
connection-sheet actions, and native HID report encoding/reference counts.

Final hardware acceptance requires an Android 9+ phone whose Bluetooth stack
exposes HID Device and a paired computer, because an emulator cannot verify
over-the-air keyboard/consumer-control delivery.
