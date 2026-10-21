# iOS build and device validation

From the repository root on a Mac with a current Xcode installation:

```sh
flutter pub get
flutter build ios --debug --no-codesign
```

The `iOS unsigned build check` GitHub Actions workflow runs the same build on
macOS when iOS, Dart, package or workflow files change. It checks compilation
and plugin linkage without a signing identity. Installing on an iPad requires
an Apple Developer team, a signing certificate and provisioning profile; set
the Runner target team in Xcode or pass the team's normal Flutter signing
settings. Device acceptance also needs a physical iPad and a same-Wi-Fi
LumiaKey Desktop host.

The iPad connects by pasting the Desktop code. Desktop lets you choose which
private IPv4 interface to advertise, so select the Wi-Fi address reachable by
the iPad when VPNs or virtual adapters are present. The token is carried in the
`x-lumiakeys-token` header. The iOS app uses unicast requests and does not
listen for UDP broadcasts, which would require Apple's restricted multicast
entitlement. The connection uses local HTTP and does not provide transport
encryption. Desktop validates keyboard chords through its existing shortcut
executor; mouse, held-key, Bluetooth HID and text-batch behavior are not
provided by this adapter.

Local speech recognition continues to use the existing `local_dictation`
package and `sherpa_onnx` plugin. Windows cannot verify CocoaPods/Swift package
resolution, native iOS compilation, microphone capture, model performance, or
real-device networking. The Mac workflow must pass before claiming native
plugin linkage; microphone permissions, iPad split-window behavior, dictation
quality and shortcut delivery still need physical iPad acceptance.

## Current delivery evidence (2026-10-20)

Four package analyses are clean. The root, Desktop, Protocol, Engine and Kotlin
suites report 212 passed tests and 0 skipped. Dart coverage for owned `lib/`
code is 6,419 of 8,423 lines (76.21%): Phone 79.23%, Desktop 62.80%, Protocol
86.61%, and Engine 82.44%. All four installer-script suites passed.

Android 1.3.0 code 2005 was installed on the connected Moto device. The APK
SHA-256 was verified against the device's `base.apk` as
`12B4CF2BDA3333B07CAC7F2F6DC68DB2C243195342529F1EDC06B0CD112423E4`.
Windows 1.3.0+5 was installed, started, and its 23 files were verified. The
installed Desktop `/info` endpoint accepted token authentication and returned
403 without a token; the check did not inject keyboard input. Existing local
model hashes were preserved on both systems.

The tablet screenshot bundle contains 69 captures. Key layouts and both iPad
screenshots were visually inspected. The ignored HTML index is
`build/ui_screenshots-tablet/index.html`; the ZIP is
`build/artifacts/LumiaKey-1.3.0-screenshots.zip`.

The unsigned iOS CI workflow is pending its post-push run. No native iOS build
or physical iPad acceptance is claimed. End-to-end dictation from real speech
through insertion into a target app has not been tested.
