# LumiaKey 1.4 editions

> Historical 1.4 flavor architecture. For the current independent Bluetooth Lite
> project, source exports, and build entry points, use [EDITIONS.md](EDITIONS.md).
> The root `lite` flavor and `lib/main_lite.dart` remain compatibility source;
> they are not the independent Bluetooth Lite product delivered in this work.

## Choose an edition

| | Lite | Regular |
|---|---|---|
| Mobile platforms | Android 9+ | Android 9+, iPhone, iPad |
| Computer connection | Direct Bluetooth HID | LumiaKey Desktop on the same local network |
| Shortcut configuration | On the Android device | On the computer |
| Initial shortcuts | General, ChatGPT, Chrome | General and installed applications published by Desktop |
| Application launching | Open/focus the application yourself | Launchpad starts/focuses the application on the computer |
| Control surface | Existing local profile layout | Landscape, left navigation, four columns by three rows, right touchpad |
| Android package ID | `com.lumiaiq.smartkey.lite` | `com.lumiaiq.smartkey` |

The two Android applications can be installed together. They use independent
configuration storage. Installing Lite does not delete Regular's saved profiles;
there is no automatic transfer between Android application sandboxes. Use profile
export/import when moving local Bluetooth profiles.

## Lite

Pair the Android device with the computer through Bluetooth, choose General,
ChatGPT, or Chrome, and open the corresponding application on the computer.
Lite sends its shortcuts to whichever application has focus. Selecting a profile
does not start or activate a computer application.

Open **Settings → Shortcut settings** to edit individual buttons. **Add or manage
profiles** opens the existing create/import/reorder tools. The existing four-profile
limit remains; the three supplied profiles leave one additional slot. User-edited
profiles are stored locally and retained when reopening the application.

Lite does not start LAN discovery, pair with Desktop, receive application
manifests, or execute Desktop actions. Its touchpad continues to use Bluetooth.

## Regular

Install the updated **1.4 LumiaKey Desktop** on the computer, then connect the mobile
application to it on the same local network. iPhone/iPad use the Desktop connection
code and require local-network permission. Configure application paths and
shortcuts in Desktop's **Apps** and **Shortcut Layout** sections.

The left navigation starts with **Launchpad**, **General**, **ChatGPT**, and
**Chrome**, followed by other detected applications when available. Launchpad
shows installed applications synchronized from Desktop; it is separate from the
Desktop app's own local eight-slot launcher. Choosing an application launches or
focuses it on the selected computer and opens its shortcut layout.

General supplies clipboard, undo/redo, selection, delete/escape, mute, volume,
and playback controls. Built-in layouts use twelve selected actions. Existing
custom layouts keep their bindings and order; additional keys and applications
remain accessible through twelve-cell pages.

The touchpad remains visible on the right. Pointer movement and clicks require
the connected Desktop to advertise mouse support. Disconnecting disables actions
and speech output instead of sending input over Bluetooth. Switching computers,
changing application context, and leaving landscape cancel pending input.

Regular requests landscape on Android and iOS. If an operating system grants a
portrait window, the control surface asks the user to rotate and does not expose
executable controls until landscape returns.

## Reproducible builds

Use Flutter 3.44.2 / Dart 3.12.2, matching the validation workflows. From the
repository root on Windows:

```powershell
./scripts/build_lite.ps1
./scripts/build_regular.ps1
```

The scripts build release APKs using the correct native flavor and Dart entry
point. Equivalent commands:

```sh
flutter build apk --release --flavor lite --target lib/main_lite.dart --dart-define=LUMIAKEY_EDITION=lite
flutter build apk --release --flavor regular --target lib/main.dart --dart-define=LUMIAKEY_EDITION=regular
```

Outputs are `build/app/outputs/flutter-apk/app-lite-release.apk` and
`build/app/outputs/flutter-apk/app-regular-release.apk`. A configured release key
is used when available; the existing local-build fallback signs APKs with the
Android debug key. Tagged publishing still requires the release signing setup.

On macOS, Regular's iOS compile check is:

```sh
flutter build ios --debug --no-codesign --target lib/main.dart --dart-define=LUMIAKEY_EDITION=regular
```

That unsigned `.app` is a build artifact, not an installable signed IPA.
Installation on an iPhone/iPad requires an appropriate Apple signing/provisioning
or distribution setup. See [Apple validation scope](APPLE_BUILD_VALIDATION.md).

Build the computer companion from `desktop_companion/` with
`flutter build windows --release` or `flutter build macos --release`. Main-push
workflows also validate both Android editions and Apple builds and retain their
artifacts; they do not publish a tagged release.

See [validation evidence and installation limits](MOBILE_EDITIONS_VALIDATION.md)
for the verified checks and the distinction between build results and physical
device acceptance.
