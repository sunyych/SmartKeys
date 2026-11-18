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

Run the Windows build and tray acceptance on Windows. Linux builds need
`clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, and `liblzma-dev`.
Shared protocol models
are in `../packages/lumiakeys_protocol/`.

Windows builds also need Rust and Cargo with the matching MSVC target
(`x86_64-pc-windows-msvc` or `aarch64-pc-windows-msvc`). The default Windows
backend uses the existing Dart and Windows runner paths. To try the Rust
backend, quit LumiaKey Desktop from the tray and launch the bundled
executable from PowerShell:

```powershell
$env:LUMIAKEY_WINDOWS_DESKTOP_BACKEND = 'rust'
& '.\lumiakeys_companion.exe'
```

This enables Rust for shortcuts, pointer batches, running and foreground
process queries, and App Paths and uninstall registry reads. The older
`LUMIAKEY_WINDOWS_SHORTCUT_BACKEND=rust` setting still enables shortcuts alone.
Registered artwork uses the existing Windows Shell icon handler. The scanner
continues to get AppsFolder and Start Menu entries through the existing Shell
query. Read-only operations can use their compatibility paths when a native
query fails or no registered icon is available. Input requests use the selected
backend once, with availability determined at startup for pointer capability.

To switch back, quit LumiaKey Desktop, clear the backend settings with
`Remove-Item Env:LUMIAKEY_WINDOWS_DESKTOP_BACKEND, Env:LUMIAKEY_WINDOWS_SHORTCUT_BACKEND -ErrorAction SilentlyContinue`,
and launch again. Use an interactive Windows desktop to verify real input and
end-to-end latency.
