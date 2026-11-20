# LumiaKey Desktop 1.2

LumiaKey Desktop is the control center for LumiaKey Android. It persists the
authoritative shortcut manifest, publishes it to the connected phone, and
executes managed shortcut, application, and URL actions.

## Runtime behavior

- Starts hidden as a System Tray app on Windows and Menu Bar/accessory app on
  macOS. Linux uses a standard GTK app window.
- Closing the settings window hides it; it does not stop synchronization.
- Tray menu: Open Settings, Open Launcher, Connected Phone, Shortcut Profiles, About, Quit.
- Settings: General, Bluetooth, Shortcut Layout, Apps, Profiles, About, Local Dictation, Launcher.
- Launcher provides eight local app keys, a live clock, and native media play/pause and output mute controls. Keys select from the managed desktop application list; their app IDs are saved separately from the phone-synced manifest. Recognizable bundled artwork is used where available, with the managed app's configured symbol as a fallback.
- Linux uses the active `.desktop` entry for installed application icons when a readable PNG is available, then falls back to bundled artwork. X11 supports app activation, shortcuts, pointer movement/buttons/scroll, and voice-input shortcuts through `xdotool`. Wayland reports input automation as unavailable because it does not allow this X11 injection path.
- Linux media play/pause uses `playerctl`; output mute uses `pactl`; GNOME appearance uses `gsettings`. Install `xdotool`, `playerctl`, and `pulseaudio-utils` for those controls. Each feature reports a clear error if its command or desktop capability is unavailable.
- Macro and Script target types are schema placeholders and cannot execute.
- The Android client submits only managed IDs. Executables and URLs stay on the
  Desktop side.

Bluetooth HID continues to carry normal keyboard/mouse input. Structured
Desktop-to-phone manifests currently use the local companion channel because
the standard HID link is not a general bidirectional data transport.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
flutter build macos --debug
flutter build linux --release
```

Desktop builds need Rust and Cargo for the runner's architecture. Windows
uses the MSVC target and macOS uses the Darwin targets listed by Xcode.
Linux builds need `clang`, `cmake`, `ninja-build`, `pkg-config`,
`libgtk-3-dev`, `liblzma-dev`, `libxcb1-dev`, and `libxcb-xtest0-dev`.
The Linux Rust backend uses the XCB and XCB XTEST runtime libraries.
Shared protocol models are in `../packages/lumiakeys_protocol/`.

## macOS TestFlight

Select **Runner-TestFlight** in Xcode to archive the native macOS app with
App Sandbox. The **Runner** scheme builds the DMG edition. Both schemes use
the existing macOS bundle identifier, `com.lumiaiq.smartkey`.

```sh
flutter build macos --release --config-only
xcodebuild -workspace macos/Runner.xcworkspace \
  -scheme Runner-TestFlight -destination 'generic/platform=macOS' \
  -archivePath build/LumiaKey-TestFlight.xcarchive archive
```

Use the signing team that owns the macOS platform in App Store Connect.
Export the archive for TestFlight once that platform and its signing are
configured.

In the TestFlight build, **General → Request** asks macOS for permission to
post keyboard and pointer events. Return to LumiaKey or select **Refresh
permission status** after granting access. The indicator reflects macOS
authorization. Verify clicks and shortcuts in a signed build against an
actual target app before releasing to testers.

Shortcuts assigned to a specific app check its bundle identifier while it is
frontmost. App Sandbox blocks verification of a focused text field in another
app. Local dictation keeps recognized text in the window for manual copying.
Phone-to-Mac dictation insertion and the global dictation hotkey are disabled
in this build. Vibe punctuation shortcuts and System Mute report an error.
The region screenshot action checks the expected app and macOS screen capture
permission before launching the capture UI.

Run `flutter test test/ui_screenshot_test.dart` to capture the TestFlight
permission and transcript states. The shared screenshot index generator at
`../scripts/generate_screenshot_index.dart` includes these states in the same
HTML page as the other current UI screenshots.

## Rust desktop backend

Quit LumiaKey Desktop and launch the bundled executable with
`LUMIAKEY_DESKTOP_BACKEND=rust` to enable Rust process and foreground reads
and pointer batches. Windows also uses Rust for shortcuts and supported
registry reads. The older Windows Desktop and shortcut-only settings remain
valid.

```powershell
$env:LUMIAKEY_DESKTOP_BACKEND = 'rust'
& '.\lumiakeys_companion.exe'
```

```sh
# macOS
LUMIAKEY_DESKTOP_BACKEND=rust "/Applications/LumiaKey.app/Contents/MacOS/LumiaKey"

# Linux, from the extracted bundle
LUMIAKEY_DESKTOP_BACKEND=rust ./lumiakeys_companion
```

On macOS, pointer control requires Accessibility and Core Graphics posting
permission. The system accepts submitted events through Core Graphics, which
does not confirm their delivery. On Linux, pointer control requires an X11
display with XTEST and is unavailable in Wayland sessions. Read-only queries
can fall back to the existing adapters if the native query fails. App
inventories and artwork continue to use the operating system's installed-app
and icon facilities.

To return to the default backend, quit LumiaKey Desktop, clear the backend
environment variables you set, and relaunch. Verify real input and latency
from an interactive desktop session.
