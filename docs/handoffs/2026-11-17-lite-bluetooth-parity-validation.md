# Bluetooth Lite 1.2 interface parity

Standalone Android Lite is **1.2.0+3**, package `com.lumiaiq.bluetoothlite`.
Full/Desktop remain **1.7.0+9**. Validated runtime commit:
`67867ae1eb61203e4f7363c9684f54906c7e878c`.

Lite now presents Full's landscape rail, brand/wordmark, top host/clock/media
row, four-column/three-row key grid and right touchpad. Its transport is Bluetooth
HID. It has no KVM, microphone/voice UI, Desktop transport, Internet permission
or online service. The Bluetooth settings page manages one paired host at a time.

The user explicitly confirmed launching **computer apps through configured
Bluetooth keyboard combinations**. Twelve local Launchpad slots store optional
keyboard bindings and profile links. Metadata alone does not enable launching.
Unconfigured tiles open their local editor without sending input. The user must
configure a matching hotkey on the computer. A successful keyboard report is not
application/foreground confirmation. Sidebar profile selection changes only the
local shortcut page. Existing saved fifteen-key profiles retain pagination;
new defaults have twelve keys, including General clipboard and media controls.

## Verification

| Check | Result |
| --- | --- |
| Final standalone Flutter suite | 72 passed |
| Flutter analysis | No issues |
| Android native unit suite | 22 passed |
| Isolation/font Python tests | 11 passed |
| Independent sparse-checkout CI | Success |
| Current widget captures | 28 |
| Offline icons in actual APK | 50; all hashes matched |
| Actual release AOT | Three ABIs contain current Lite surface |
| Build inputs | 89 runtime/resource inputs matched clean source |

The independent CI is [run 44257903338](https://github.com/sunyych/SmartKeys/actions/runs/44257903338).
It validates without Full's parent pubspec/lib and builds Android separately.
The local optimized release was built from a fresh NTFS export, with the Gradle
daemon disabled. Real APK checks include its package/version, signature,
permissions, AOT code, brand asset, offline icon bytes and native host-guard code.

The controller rejects input outside a resumed landscape control context and
rechecks saved launch authority. Old successes/failures cannot replace a new host
or publish false launch success. Saved DTOs are deeply immutable. Native queues
capture the expected host and input epoch; cancellation replies once, and success
is returned only after the report's press and release complete. Profile/proxy
changes invalidate old queued input, including reconnects with the same address.
Healthy Bluetooth snapshots clear connection errors while preserving input and
configuration errors. Startup/resume enter the same immersive mode as Full.

## Installation

The existing phone was upgraded from Lite **1.1.0/code2** to **1.2.0/code3** using
`adb install -r`, preserving data and existing permissions. No new permissions
were granted, no profiles or launch bindings were saved during acceptance, and
no test shortcut/media/pointer action was sent to personal applications.

Physical acceptance verified the final fullscreen home, brand/header/grid/
touchpad, absent KVM/voice controls, and the unconfigured-slot editor. A launch
binding remains for the user to configure with their computer's corresponding
hotkey. The phone is left in Lite's Launchpad.

Final optimized APK SHA-256:
`5a9f28f702fbdfb53402852c499427f1b8b5dbb7875f3e960666dfad402d1233`.
It uses the existing Android development certificate
`1136bc3a6e1408d11013e7e3d9e2c9dc4ca716da2cfc2887a3c82944956af7b8`.
Production-store signing, OS-specific launch-hotkey setup and real shortcut
delivery to personal apps are separate from this acceptance. Screenshots in the
delivery gallery are widget fixtures; private physical-screen captures remain
outside the distributable screenshot ZIP.
