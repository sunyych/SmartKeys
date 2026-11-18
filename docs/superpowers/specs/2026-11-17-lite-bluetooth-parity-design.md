# Lite Bluetooth interface parity

The user requests the same landscape control surface as current Full: top rail
brand/wordmark, left Launchpad/General/application navigation, central twelve-key
grid (four columns, three rows), right touchpad, and host/clock/play/mute header.
Lite remains independent Android Bluetooth HID. It has no KVM, voice input,
Desktop service, network, account or online icon/log transport. The user confirmed
that Launchpad sends a configured Bluetooth keyboard combination to launch an
application on the computer, rather than opening an Android application.

Standalone Lite becomes **1.2.0+3**; Full/Desktop stay **1.7.0+9**. Preserve
`com.lumiaiq.bluetoothlite` and the current upgrade certificate and saved data.
Do not import Full Dart code or add production dependencies. Reproduce its
presentation in Lite-owned files and reuse the existing offline touchpad gestures.

## Behavior and data

Launchpad contains twelve local slots. A slot has a title, optional offline icon,
optional profile ID and nullable keyboard launch shortcut. Default ChatGPT/Chrome
metadata is visible with no launch combination. Only an explicitly saved, valid
keyboard binding can enable launching; a name or icon alone never enables it.
The existing `sendStep` keyboard channel sends that exact combination. The user
must also arrange its meaning on the computer. HID acceptance is not application
or foreground confirmation. Do not add OS-launch commands, paths or app discovery.
After a successful chord, show a linked local profile, or remain on Launchpad if
there is no linked profile. Selecting a sidebar profile only changes the local
page and never launches anything.

Persist launcher slots separately from existing `lite.profiles.v1`; retain legacy
profile/shortcut migration and saved 15-key lists. New default profiles use twelve
keys; longer saved lists paginate without truncation. Extend LocalShortcut with a
validated consumer-control variant so General can include clipboard and media
actions. Launch bindings must remain keyboard-only. Default General includes six
clipboard/edit keys and six media keys; keep ChatGPT/Chrome keyboard presets.
Settings provides local profile/shortcut editing, twelve launcher-slot editors,
Bluetooth management, offline icon library and local error logs. Saving must
complete before new launch authority is published. Failed loads must not overwrite
saved data; failed saves preserve the last durable in-memory configuration.

## Controller and input contract

Extract LiteController from main.dart to own state, persistence, method-channel
events, native errors and input guards. All key/media/pointer actions require a
connected captured host, landscape, resumed lifecycle and an active control
surface. Settings, profile/page changes, host changes, portrait and background
cancel old pointer epochs and release held input. A pending launch rechecks its
slot binding and host before dispatch; errors return failure, never fake success.
No sticky modifier may silently alter a saved launch combination.

LiteController exposes profiles, launcherSlots (exactly twelve), selectedProfileId,
connected/status/activeHost/pairedHosts, loading/saving/error/inputEpoch and
diagnostics. It owns initialize/dispose, refreshPairedHosts/connect/disconnect,
selectProfile, executeShortcut, launchSlot, sendConsumer, movePointer/scrollPointer/
primaryClick/secondaryClick, saveProfile/deleteProfile, saveLaunchSlot,
setLandscape/setControlsVisible and handleLifecycle. Input methods return success
booleans; configuration methods throw on failed persistence for editor feedback.
Slot/store DTOs and exact signatures are frozen by the core coder before UI wiring.

## Ownership and verification

Luna core: models/stores/controller/main bootstrap, migrations and behavior tests.
Luna interface: new home surface, touchpad presentation, brand asset/pubspec and
layout/screenshot tests. Luna platform: settings/editors, Android landscape
declaration, native/isolation review and its tests. Root coordinates, reviews,
builds, verifies real APK code/signature/resources, commits/pushes/merges and
updates the existing phone without clearing data.

Tests must prove unconfigured/disconnected/portrait/background/settings states
produce no input; saved bindings send exactly one intended keyboard action;
failure/host changes/edits cannot produce false launch success; old data survives;
consumer controls use HID; every key page contains at most twelve cells; labels
and top controls fit phones/tablets and larger fonts; and no KVM/microphone or
Full transport exists. Preserve native gesture/release regression coverage.
Run standalone Lite analysis, complete Flutter and Android native tests, source
and APK isolation, generated catalog/vendor checks and fresh independent export.
Build release from a clean NTFS source directory to avoid stale Gradle JNI merge
outputs. Inspect actual packaged AOT for new Lite UI markers, all fifty offline
icons, the real brand asset, version and matching upgrade signature. Physical
verification performs only navigation, never shortcuts to personal applications.
