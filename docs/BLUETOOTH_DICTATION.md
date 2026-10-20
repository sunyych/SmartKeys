# Bluetooth dictation and offline installer delivery

LumiaKey recognizes microphone audio with the selected model on the phone. The
default **Bluetooth** output mode is English-only and sends final text as
keyboard reports to the paired computer. It does not require Desktop Companion
or a network receiver. Chinese and other multilingual output require the
explicit **LumiaKey Desktop** mode described below. Model downloads require a
connection once; recognition uses the local model thereafter. No audio
recording is saved by dictation, and audio is never sent to Desktop.

The application-voice button remains a separate shortcut for the selected
computer application's own voice-input feature. Its microphone processing and
privacy depend on that application. The two buttons use different icons, and
the first-use explanation distinguishes them.

Tap the dictation microphone to quick-start with the last selected output. On
first use, or if the selected model is missing, LumiaKey opens setup instead of
starting capture. Long-press the microphone to always open output, model, and
recognition-language settings, even when the model is ready and quick-start
would begin immediately.

While listening, LumiaKey returns to the phone's shortcut controls and keeps
them usable. A compact **44 × 40** corner control combines Stop with a live
microphone-level indicator in both Bluetooth and Desktop modes. The level comes
from the existing in-memory PCM stream; no recording is created or sent. Stop
returns to the home screen. Back or opening settings cancels capture, and
returning to the app does not restart dictation automatically.

## Bluetooth output

Bluetooth output is deliberately English-only. It requires an English input
state and a US keyboard layout because the phone encoder emits US key codes.
Recognition language and app display language do not change this output
contract. The complete phrase is validated before output; unsupported text
fails closed. The app does not
change host settings, switch output modes, or retry a failed or uncertain
phrase.

When upgrading from a build that stored a Bluetooth Unicode/HexNumpad choice,
the stale preference migrates to the safe English Bluetooth mode. LumiaKey does
not edit or remove Windows registry values.

Older validation notes record a manually approved
`HKCU\Control Panel\Input Method\EnableHexNumpad` value and HexNumpad setup
steps. Those records are historical evidence and are superseded by the current
English-only Bluetooth policy. HexNumpad is not a supported output mode; the
existing registry value is not needed for current LumiaKey dictation.

## LumiaKey Desktop output

Select **LumiaKey Desktop** explicitly for Chinese and other multilingual
output. The phone still captures audio and runs ASR locally; it sends only
finalized transcript text to the authenticated Desktop companion over the same
LAN. Desktop uses its Unicode text-insertion adapter for the focused external
application. No audio or interim transcript is transferred.

This mode requires a discovered, compatible Desktop host advertising the
dictation receiver. If that host is absent, becomes stale or changes during
capture, dictation cancels the session. A confirmed `input_busy` result means
the native injector rejected the phrase before inserting any characters; the
phone drops that phrase and keeps listening so a later phrase can be captured.
A manually triggered shortcut preemption also drops the interrupted phrase and
keeps listening. Neither case replays the phrase. Unknown or partial native
insertion failures cancel the session, with no automatic retry or Bluetooth
fallback. Success is acknowledged only after the complete text submission is
reported by the native sink.

For Bluetooth output, delivery is serialized, bounded and pinned to the selected
Bluetooth host.
Disconnecting, switching hosts or backgrounding cancels pending output and
releases held keys. Failed or partially sent phrases are not automatically
retried. Bluetooth accepting a report does not prove that the focused
application inserted its character.

## Desktop installers on the phone

Tagged release CI builds Windows and macOS packages first. The Android job
bundles those packages from the same workflow run, together with version,
commit, size and SHA-256 metadata. The release fails if either package is
missing. Installer binaries, generated catalogs and screenshots are build
outputs excluded from Git.

The Android installer screen can verify an embedded package and export it to a
user-selected local shared-storage folder. Export checks the package and refuses
to replace an existing filename. The computer can copy the exported file using
Android USB file transfer (MTP).

The accepted phone-transfer design is a user-selected local shared-storage
folder followed by USB file transfer (MTP). MTP exposes ordinary phone files;
it does not provide a USB mass-storage disk or a Windows drive letter. A true
virtual disk is outside this implementation's scope and is not a pending
deployment choice. Development APKs without a release catalog explicitly show
that no desktop installers are bundled.

## Validation boundaries

Automated tests cover Bluetooth output policy, authenticated Desktop text
delivery, exact UTF-8/Unicode preservation, cancellation and host changes,
first use, installer metadata and export errors. Widget captures cover
application screens without committing screenshots. They are deterministic
Flutter renders, not physical-phone captures. Real Bluetooth input into a
controlled target, ARM64 install/reinstall, and native macOS packaging remain
separate acceptance checks; report their evidence independently.

Platform references: [AOSP UsbManager](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/hardware/usb/UsbManager.java),
[Android shared-document storage](https://developer.android.com/training/data-storage/shared/documents-files),
[QMK Unicode input modes](https://github.com/qmk/qmk_firmware/blob/master/docs/features/unicode.md).
