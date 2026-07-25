# LumiaKeys

LumiaKeys is a desktop-driven shortcut platform with an Android Bluetooth HID
control surface. The Android phone app requires Android 9 (API 28) or later.
This monorepo also contains the independent LumiaKeys Desktop app in
`desktop_companion/` for Windows and macOS.

## Implemented V1.2

- LumiaKeys Desktop is the authoritative source for Desktop-executed Codex and
  application layouts, installed/running application state, semantic icon IDs,
  and managed shortcut mappings. Android remains the source for its General,
  Web, Zoom / Teams, and Custom Bluetooth HID Profiles.
- The Desktop app starts without opening its settings window. Windows keeps a
  System Tray icon and macOS uses an accessory/Menu Bar app. Its menu exposes
  Open Settings, Connected Phone, Shortcut Profiles, About, and Quit.
- The settings window contains General, Bluetooth, Shortcut Layout, Apps,
  Profiles, and About sections. General owns Enable Apps Sync, Auto Launch
  Apps, Sync Icons, Current Connected Phone, and Current Shortcut Profile.
- Shortcut Layout edits Button Name, Icon, Target Type, Shortcut, Launch App,
  URL, and Description. Keyboard Shortcut, Launch Application, and Open URL are
  executable in V1.2. Macro and Script are modeled but intentionally disabled.
- Apps Manager detects the supported catalog (including Codex / ChatGPT,
  Photoshop,
  Illustrator, VSCode, SolidWorks, Premiere, and Chrome) on the current
  computer. Only detected applications are sent to Android; a three-second
  runtime reconciliation marks which of those apps are running.
- The Android top strip is one unified control surface. All local Profiles are
  available while Desktop is offline; Desktop sync keeps General as the HID
  fallback and replaces Web, Zoom / Teams, and Custom tabs with managed Apps
  and Workspaces. The top-right control-menu pill displays the highest useful
  state: foreground app, Desktop, then HID.
- Apps is a launch-only square button grid using offline brand icons. Tapping
  Chrome, Codex, or VSCode sends its managed application ID to Desktop and
  immediately opens that application's shortcut layout. Chrome ships a
  15-button common layout for navigation, tabs, clipboard, bookmarks, password
  manager, media, mute, address, and refresh.
- macOS maps the installed/running `ChatGPT.app` process to the Desktop-owned
  Codex application ID, so the phone shows one `Codex / ChatGPT` Workspace
  without exposing a process name or executable path as an action.
- Codex uses the same 3 × 5 / 5 × 3 key region and the existing wheel/touchpad,
  rather than replacing the whole app. Its editable defaults prioritize Open
  Codex, Dictation, New/Previous/Next Chat, Send, search, folder, command menu,
  Terminal, Review, navigation, and Sidebar actions documented by Codex.
- Settings records shortcut counts in a separate phone-only preference. It
  shows most/least-used shortcuts, can reorder the current local Profile by
  usage, and states explicitly that the data is never sent to Desktop/cloud or
  included in Profile exports.
- Android does not persist Desktop manifests. It discovers Desktop, fetches the
  current manifest, watches its revision, renders it in memory, and sends only
  `buttonId`, `applicationId`, or `profileId`. Desktop resolves and executes
  the actual shortcut, executable, voice-input request, or URL.
- Shared wire models live in `packages/lumiakeys_protocol/`. Manifest schema 1
  validates layout/profile/app references and globally unique button IDs.

### V1.2 transport boundary

Bluetooth HID remains the keyboard/mouse input path. The existing HID profile
does not expose a general Desktop-to-phone data channel to Flutter, so the V1.2
structured manifest uses the authenticated local companion channel (UDP
discovery on port 45832 plus an ephemeral-token HTTP endpoint). Both devices
must currently be on the same local network. `CompanionService` is the transport
boundary for a later custom BLE or vendor-HID transport without changing the
manifest, controller, or UI layers.

## Implemented V1.1 supplement

- Portrait uses one shared 15-button state in a 3 × 5 grid.
- Landscape left/right uses the same state in a 5 × 3 grid, with buttons and
  the profile navigation control arranged in a 2:1 split.
- Rotation clears held-button state, cancels active wheel/mouse input, and
  invokes `releaseAllKeys()` without recreating the Profile or connection
  controller.
- LumiaKeys starts in Landscape by default. Portrait and Auto remain available
  only through Screen Orientation in Settings, and the choice persists.
- Configuration schema v7 owns an ordered list of independent Profiles, each
  with 15 buttons, navigation actions, icon, optional target application,
  accent color, and timestamps.
- Cross-platform shortcuts use `PRIMARY`: Automatic mode maps it to Command on
  Apple hosts and Ctrl on Windows/Linux hosts, with an explicit manual override
  in Settings when a Bluetooth computer name is ambiguous.
- The General default matches `docs/screenshots/default_general_layout.png`;
  the final touchpad result is in
  `docs/screenshots/final_touchpad_fullscreen.png`:
  mute/volume/undo/redo, media/open/Dark, then cut/copy/paste/close/delete.
- Dark is a toggle. Its dark state holds the LumiaKeys phone window at 10%,
  dims the host display and keyboard illumination, and the next tap restores
  the phone's charging/system brightness plus brightens the host again.
- General uses a full touchpad on the right. Drag with one finger to move the
  pointer, tap to left-click, scroll with two fingers, or tap with two fingers
  to right-click.
- The controller runs in immersive full-screen mode. A compact floating menu
  keeps profiles, Bluetooth, editing, and settings available without a top bar.
- Edit mode keeps tap-to-configure and adds long-press drag-and-drop: dropping
  one button on another swaps their complete configurations and persists the
  new order.
- The free edition starts with exactly four JSON-backed slots: General, Web,
  Zoom / Teams (Windows), and Custom. Photoshop and SolidWorks are retired.
- A compact horizontal strip above the key grid switches Profiles immediately;
  the floating menu still opens the full Profile selector and management flow.
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
  lists already paired hosts, remembers and reconnects the last selected
  computer, and sends keyboard, consumer-control, mouse movement, click, and
  mouse-wheel reports. An explicit Disconnect clears the remembered host.
- Platform launcher icons are generated from
  `assets/app_icon/app_icon_source.png`. Android 8+ uses a deep-blue adaptive
  background with the transparent safe-zone foreground in
  `assets/app_icon/adaptive_foreground_source.png`.
- LumiaKeys Desktop uses that same LK source artwork for the macOS AppIcon,
  macOS Menu Bar icon, and multi-resolution Windows `.ico`; the Companion does
  not use Flutter's default logo.

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
paired devices. Ordinary keyboard and mouse actions need no desktop software;
app launching, voice input, and reliable OS detection use the Companion.

## LumiaKeys Desktop

The desktop app is a separate product under `desktop_companion/`; it is not
compiled into the phone app. It starts in Menu Bar/System Tray mode. Select
**Open Settings** from the icon after launch.

```sh
cd desktop_companion
flutter run -d macos    # or windows on that operating system
```

It broadcasts protocol v2 discovery on UDP port 45832 and serves manifest and
action endpoints on an ephemeral TCP port. A fresh random token is created on
every run. Synced Android actions contain only Desktop-owned identifiers;
legacy validated `launch`, `shortcut`, and `voiceInput` requests remain
compatible. Arbitrary shell requests are rejected.

## Tagged GitHub releases

Pushing a new `vMAJOR.MINOR.PATCH` Tag from a commit contained in `main`
creates one GitHub Release with a signed Android APK, a macOS DMG, a Windows
EXE installer, and SHA-256 checksums. Ordinary branch pushes do not publish
assets. The Tag is the Flutter build version, so V1.2 is released as `v1.2.0`.

Android release signing secrets must be configured before the first Tag is
pushed. Setup, asset names, validation rules, and the exact release command are
documented in [`docs/GITHUB_RELEASES.md`](docs/GITHUB_RELEASES.md).

## Pair and connect

1. Open LumiaKeys and tap the Bluetooth status chip, or open Settings →
   **Computer connection**.
2. Grant Nearby devices access if Android asks.
3. Tap **Make phone discoverable**.
4. On Windows, open **Add Bluetooth device**; on macOS, open Bluetooth
   Settings. Pair the phone from the computer.
5. Return to LumiaKeys, tap **Refresh**, and connect the paired computer.

Pairing is managed by Android/Windows. LumiaKeys retains no separate pairing
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
(cd packages/lumiakeys_protocol && dart test && dart analyze)
(cd desktop_companion && flutter analyze && flutter test)
(cd desktop_companion && flutter build macos --debug)
```

Automated coverage includes portrait/landscape grids, landscape ratio, held-key
rotation safety, touchpad movement/click/right-click/two-finger scrolling,
edit-mode drag reordering, persisted editor saves, quick Profile switching,
the four-slot limit and replacement, community pack installation, JSON
validation, template loading,
built-in/custom/missing-image rendering, orientation persistence, schema
v1/v2/v3/v4/v5/v6 → v7 migration, automatic Command/Ctrl resolution,
connection-sheet actions, synced Apps/Codex navigation and managed-ID actions,
manifest serialization/validation, Desktop API token checks, Desktop editor
persistence, and native HID report encoding/reference counts.

Final hardware acceptance requires an Android 9+ phone whose Bluetooth stack
exposes HID Device and a paired computer, because an emulator cannot verify
over-the-air keyboard/consumer-control delivery.
