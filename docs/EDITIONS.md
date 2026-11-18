# LumiaKey editions

Current versions are **Full / Desktop 1.8.0+10** and independent
**Bluetooth Lite 1.3.0+4**. The shared-package Android
`lite` flavor and `lib/main_lite.dart` remain historical 1.4 compatibility
source and are not the independent Lite product. See
[the 1.4 validation record](MOBILE_EDITIONS_VALIDATION.md) for those older builds.

Full has mobile and Desktop companion projects; Bluetooth Lite builds independently.
The [App library](APP_LIBRARY.md) binds canonical artwork and OS-specific shortcut
profiles. Full is configured on Desktop; Lite installs bundled profiles locally
for an explicitly selected computer OS. Existing profiles and launch keys survive.

Lite 1.2 uses the same landscape rail, header, twelve-key grid and right touchpad
as Full. Its header shows the Bluetooth host, clock and media controls. Launchpad
slots send saved keyboard combinations over Bluetooth; the user configures the
corresponding app-launch shortcut on the computer. Unconfigured slots open a local
editor and send no input. Sidebar profile selection changes only the local page.
Lite settings manage profiles, media shortcuts and launch bindings on the phone.
It has no KVM, microphone/voice feature, Desktop transport or online service.
See [Lite 1.2 validation and phone installation](handoffs/2026-11-17-lite-bluetooth-parity-validation.md).

Full 1.7 keeps twelve landscape keys and the right touchpad. Its shared top bar
places host, clock and media controls next to the current workspace title; the
LumiaKey wordmark sits below the brand icon at the top of the rail. Desktop can
search all OS-discovered launchable apps and add portable/unindexed programs
through a local file picker. These additional apps provide launch-only keys;
the existing managed profiles retain their shortcut and foreground behavior.

| Edition | App project | Platforms | Includes |
| --- | --- | --- | --- |
| Full mobile | repository root | Android, iPhone, iPad | Desktop-connected controls, profiles, setup, fifty offline icons and configurable online additions |
| Desktop companion | `desktop_companion` | Windows, macOS, Linux (X11 input) | Desktop-owned applications and shortcuts, native artwork and the same fifty bundled icons |
| Bluetooth Lite | `apps/bluetooth` | Android only | Bluetooth HID keyboard, mouse/touchpad, media controls, local shortcut editing, fifty offline icons and local error logs |

Full error diagnostics stay local unless the user separately allows sharing;
sharing defaults off and uses only a configured HTTPS center. Lite has no
network uploader. See [icon library and diagnostics](FULL_ICON_LIBRARY_AND_DIAGNOSTICS.md)
and [artwork sources and terms](APP_ICON_SOURCES.md).

Bluetooth Lite has its own Flutter package, Android Gradle project, `applicationId` (`com.lumiaiq.bluetoothlite`), launcher, manifest, and entry point. It does not depend on root Flutter packages, desktop companion code, community server code, account services, or the local dictation package. Its manifest declares nearby Bluetooth permissions only; it does not request Internet or microphone access. The Android HID controller keeps the paired-device flow, runtime permission requests, host switching, connection errors, and key release behavior.

Full retains the confirmed twelve-cell, four-column by three-row landscape-only
mobile surface. The handoff's older eight-slot/portrait design does not replace
that choice. Lite retains its standalone keyboard, mouse, media and local
shortcut screens. Its General, ChatGPT and Chrome profiles are edited on the
phone; opening a profile never launches an app on the computer. Default key
combinations use Ctrl. The App library provides explicit macOS defaults for new
profiles; existing custom shortcuts are not automatically converted.

The independent Lite package coexists with Full and with the older
`com.lumiaiq.smartkey.lite` installation. It does not remove, replace or read the
private data of either app. A debug APK is a development-signed validation
artifact. Release signing still requires all four Android signing environment
values; an unsigned release APK is not an installable release delivery.

The [earlier 1.5 / Lite 1.0 handoff validation](handoffs/2026-11-17-completion-validation.md)
records those prior artifacts and installations. Current artifact sizes,
signatures and platform results are in the
[1.6 / Lite 1.1 completion validation](handoffs/app-icon-library/COMPLETION.md).
The subsequent [1.7 installed-application and header validation](handoffs/2026-11-17-installed-launchpad-and-header-validation.md)
records the current Full/Desktop increment and installation scope.

## Build

```sh
./scripts/build-full.sh apk --release
./scripts/build-full.sh ios --no-codesign
./scripts/build-full.sh linux --release
./scripts/build-bluetooth-lite.sh apk --debug
# Windows: scripts/build_lite.ps1 -Configuration debug
# Independent export: scripts/build.sh apk --debug, from the Lite directory
```

Full version tags retain the `vMAJOR.MINOR.PATCH` convention, while a future
independent Lite release can use `bluetooth-vMAJOR.MINOR.PATCH`. This integration
does not create or push tags or Releases. The Lite workflow builds artifacts
from a sparse checkout containing only `apps/bluetooth`; it asserts Full's
parent `pubspec.yaml` and `lib/` are absent before verification. The exported
Lite also includes a workflow that runs with Lite as the repository root.
Linux runtime controls use X11; unsupported Wayland automation must not be
described as validated Linux input support.

## Export source folders

`./scripts/export-editions.sh /path/to/new-export-directory` exports Full and Lite into separate source folders without creating Git repositories or remotes. The destination must be new and outside this repository. It refuses to overwrite an existing destination, excludes generated build output and signing/local configuration files, and includes a self-contained Lite build/test/screenshot workflow.

On Windows use `python scripts/export_editions.py C:\path\to\new-export`.
The Python standard-library exporter needs no rsync. Source links and Windows
junctions/reparse points are rejected, and copying completes in a fresh staging
directory before claiming the destination. Full exports omit `apps/bluetooth`,
the independent Lite workflow/build entry points, and generated Desktop installer
payloads. Only the two checked-in Rust test fixtures
`community_server/tests/fixtures/test-rsa-{private,public}.pem` are allowed through
the PEM filter; all other PEM/private signing files remain excluded.

## Shortcuts

Lite shortcuts and launch bindings are edited locally and persisted in Android
app preferences. The twelve launch slots are separate from existing profiles;
new default profiles have twelve entries and longer saved lists retain pagination.
Keyboard and media shortcuts remain offline Bluetooth HID actions. Saving must
finish before a new launch binding is enabled. Profile navigation and editing
never send a launch command. The computer must have a matching launch shortcut;
Bluetooth acceptance does not confirm application startup or foreground focus.

The new profile store preserves a WIP `lite.shortcuts` list as a Custom profile;
it does not delete the old preference. A failed save leaves the previously
displayed/persisted shortcuts intact and shows an error. Native and Flutter
background handling release input and clear pending modifiers.

Run `python scripts/check_isolation.py --apk build/app/outputs/flutter-apk/app-debug.apk`
inside Lite after building. It checks the actual APK manifest/package and rejects
Full-only assets/native libraries, in addition to source, lockfile and plugin
boundaries. Final execution evidence is recorded separately after running the
current checks; the WIP handoff is not build-validation evidence.
