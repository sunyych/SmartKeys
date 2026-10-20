# Bluetooth dictation and offline installer delivery

LumiaKey recognizes microphone audio with the selected model on the phone. The
quick-dictation button sends final text as Bluetooth keyboard reports to the
paired computer; this path does not require Desktop Companion or a network
receiver. Model downloads require a connection once; recognition uses the local
model thereafter. No audio recording is saved by dictation.

The application-voice button remains a separate shortcut for the selected
computer application's own voice-input feature. Its microphone processing and
privacy depend on that application. The two buttons use different icons, and
the first-use explanation distinguishes them.

## Keyboard compatibility

The default **US ASCII** profile encodes printable ASCII for a US keyboard
layout. Set the computer to an English input state and focus the text field
before starting. The complete phrase is validated before output. Unsupported
characters and overlong phrases produce an error without typing a partial
prefix. Changing the recognition language does not change the host's keyboard
encoding.

An explicit **Windows Unicode HexNumpad** profile can type printable BMP text,
including Chinese, Japanese, Korean, and ASCII. Before selecting it, manually enable
`HKCU\Control Panel\Input Method\EnableHexNumpad` as a `REG_SZ` value of `1`,
then sign out and back in or restart Windows. Keep Num Lock on and use a tested-
compatible foreground app. LumiaKey does not edit the registry. Emoji, control
characters, other unsupported characters, and non-BMP text are rejected as a
whole phrase. This profile has not been accepted on every Windows app or real
computer, so verify it in the intended target before relying on it.

Output is serialized, bounded and pinned to the selected Bluetooth host.
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

MTP exposes phone files; it does not provide a USB mass-storage disk or a Windows
drive letter. Creating that kind of virtual disk requires Android system/device
support unavailable to an ordinary application. A true drive implementation is
pending a supported deployment choice. Development APKs without a release
catalog explicitly show that no desktop installers are bundled.

## Validation boundaries

Automated tests cover keyboard encoding, cancellation and host changes, first
use, installer metadata and export errors. Widget captures cover application
screens without committing screenshots. Real Bluetooth input into a controlled
target and native macOS packaging remain separate acceptance checks.

Platform references: [AOSP UsbManager](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/java/android/hardware/usb/UsbManager.java),
[Android shared-document storage](https://developer.android.com/training/data-storage/shared/documents-files),
[QMK Unicode input modes](https://github.com/qmk/qmk_firmware/blob/master/docs/features/unicode.md).
