# LumiaKeys Desktop 1.2

LumiaKeys Desktop is the control center for LumiaKeys Android. It persists the
authoritative shortcut manifest, publishes it to the connected phone, and
executes managed shortcut, application, and URL actions.

## Runtime behavior

- Starts hidden as a System Tray app on Windows and Menu Bar/accessory app on
  macOS.
- Closing the settings window hides it; it does not stop synchronization.
- Tray menu: Open Settings, Connected Phone, Shortcut Profiles, About, Quit.
- Settings: General, Bluetooth, Shortcut Layout, Apps, Profiles, About.
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
```

Run the Windows build and tray acceptance on Windows. Shared protocol models
are in `../packages/lumiakeys_protocol/`.
