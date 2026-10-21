# Tablet shortcut board and iPad client

## Intended behavior

The user-facing setup guide is `docs/TABLET_SUPPORT.md`.

LumiaKey gains a keyboard-only board for tablets. Automatic mode selects it
when the current window's shortest dimension is at least 600 logical pixels;
compact windows retain the existing phone keyboard and wheel. Users may
explicitly choose automatic, phone controls, or shortcut board in Settings.
The board defaults to 40 keys per screen. Settings and JSON configuration accept
any integer from 24 through 60, with 24, 40 and 60 as useful presets. The
existing profile/application navigation, editing, connection menu and local
dictation chip remain available. The wheel and mouse pad do not occupy board
space. Landscape and portrait use different column counts and fill the usable
screen without scrolling the current bank.

Existing 15-key profiles remain intact. Up to 60 local positions are supported;
unused board slots can be edited without losing existing buttons. Banks expose
additional positions without truncation. Phone mode shows at most 15 keys per
bank, preserving its existing layout. Profile import/export must round-trip
positions through 59, reject malformed positions, and retain legacy profiles.
Remote Desktop layouts use the same board capacity and bank navigation, with
exactly the existing remote button IDs and execution paths.

Changing profile, bank, orientation or window size must release held input.
Listening dictation stays on the board with its nonmodal Stop/level chip.
No new audio transport, recording, cloud service, or automatic text replay is
introduced.

## Connection and platform scope

Android retains native Bluetooth HID. The new iOS/iPadOS runner uses LumiaKey
Desktop over the existing authenticated local network channel. This is a
deliberate supported route, not a claim that Android's HID Device API exists
on iPadOS. General local keyboard buttons execute as atomic Desktop shortcuts;
held-key/mouse behavior is not advertised for the iPad transport. Unsupported
actions produce visible errors rather than pretending to succeed.

Add explicit manual pairing on both clients: Desktop offers a connection code
containing its local IPv4 address, ephemeral port and session token. The tablet
can paste it. Validate the input, verify authenticated server information and
manifest, and poll the selected server using unicast HTTP. Connection failures
clear ready state; late responses cannot replace a newer selected host.
Tokens stay in memory, are not included in screenshots/logs or URL requests,
and are sent only using the existing token header. Do not add an unauthenticated
pairing endpoint or promise encryption: the current transport is local HTTP.

On iOS disable UDP discovery by default, since broadcast needs Apple's
restricted multicast entitlement. Declare local network/microphone/image
permissions, permit local networking, support iPad device family and all iPad
orientations, and supply the existing power/brightness channel appropriately.
Prefer dynamic window layout over orientation locks for iPad multitasking.
Use bundle identifier `com.lumiaiq.smartkey` and display name `LumiaKey`.

## Implementation boundaries

1. Configuration worker: preferences, 60-position compatibility, safe editing,
   Settings, controller methods and focused persistence tests.
2. Layout worker: Home/board widgets, bank navigation, pointer cleanup,
   responsive interactions and deterministic tablet screenshots.
3. iPad/connection worker: iOS project, platform selection, LAN shortcut
   adapter, authenticated manual connection, Desktop connection UI and tests.

Root performs research, interface review, integration, full analysis/tests/
coverage, Android and Windows builds/installation, HTML screenshot generation,
commit and push. Source is tested from the existing NTFS validation checkout.
Generated screenshots and HTML remain ignored. No Mac/Xcode or connected iPad
is available on this Windows host: iPad compilation, signing and physical input
acceptance must remain explicitly unverified. Provide a Mac validation command
and an unsigned iOS CI build check where feasible.

## Research basis

- [Flutter adaptive layout](https://docs.flutter.dev/ui/adaptive-responsive/general):
  use available window constraints rather than a device-name test.
- [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy):
  direct local networking requires permission; receiving UDP broadcast on iOS
  additionally requires the restricted multicast entitlement.
- [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup):
  native iOS builds and device signing require macOS/Xcode.

These references support the platform and layout choices. The repository's
Android-only HID implementation and existing Desktop shortcut executor were
inspected directly; iPad Bluetooth peripheral behavior was not demonstrated.
