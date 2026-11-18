# Independent Bluetooth Lite validation

Validation date: 2026-11-17. Independent package:
`lumiakey_bluetooth_lite`, version `1.0.0+1`, application ID
`com.lumiaiq.bluetoothlite`. These checks concern the independent project,
not the historical root `lite` flavor.

## Source and exported project

- Independent production dependencies: Flutter and `shared_preferences` only.
- Dart 3.12.2 / Flutter 3.44.2 offline dependency resolution succeeded.
- Independent exported project's analysis reported no issues.
- All 12 Flutter tests passed in both the source project and the exported
  project, covering keyboard/mouse reports, single-use Shift without phantom
  letters, background release, save failure, General/ChatGPT/Chrome defaults,
  legacy shortcut migration, corrupt saved data, media, two-finger gestures,
  and current screenshots.
- Android native tests: **14 passed**, zero failures/errors/skips. These include
  a modifier-only Shift report whose six ordinary key usages stay zero.
- Safe source exporter: **5 tests passed**, covering fresh output, exclusions,
  existing destination refusal, source link refusal, and concurrent destination
  creation without overwrite. Only the two public Rust RSA test fixtures are
  allowed through the private-key exclusion rules.

An actual fresh source export was created outside the parent repository at
`C:\Users\sunyy\AppData\Local\Temp\LumiaKey-source-export-85862c2885254bc0bf5e4920a0f12b16`.
Within its `lumia-key-bluetooth-lite` directory, offline pub get, analysis,
all tests, the official Flutter debug APK build, APK isolation checks, native
JUnit and signature verification all succeeded. Its generated package config
contains no dependency path back to `D:\Projects\SmartKeys`.

The Full folder in that first export was an intermediate integration snapshot;
it is not final Full delivery evidence. Generate a fresh export after the
integration review. The Lite CI sparse checkout independently asserts that
the parent Full source and pubspec do not exist before building.

## APK evidence

Both official Flutter debug builds returned success and placed APKs at the
expected paths:

- Source project: `apps/bluetooth/build/app/outputs/flutter-apk/app-debug.apk`.
- Exported project: `lumia-key-bluetooth-lite/build/app/outputs/flutter-apk/app-debug.apk`.

The exported APK's signature verified as `CN=Android Debug` (development
signature). Release signing protection was retained; no unsigned release APK
is presented as an installable release. These tests did not install, replace,
or uninstall any existing phone application.

The actual source/export APK checks found only the four Bluetooth permissions
and AndroidX's package-private receiver permission. Neither APK requests
Internet or microphone access. The checks also reject Full-only ASR, account,
dictation, or Desktop installer assets/libraries.

On this Windows machine the D: workspace and C: Pub cache require disabling
Kotlin's cross-drive incremental path conversion for the process:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-17'
flutter build apk --debug --no-pub `
  --android-project-arg=kotlin.incremental=false `
  --android-project-arg=kotlin.compiler.execution.strategy=in-process
```

`scripts/build_lite.ps1` supplies these project arguments. The independent C:
export also built using the ordinary Flutter command without those arguments.
No global Java/Gradle configuration or SDK source files were edited.

## Logs and current screenshots

- `build/handoff-1.5.0/logs/bluetooth-export-verification.log`
- `build/handoff-1.5.0/logs/bluetooth-export-native.log`
- `build/handoff-1.5.0/logs/bluetooth-source-build.log`

Current screenshots are written under the shared screenshot root's
`bluetooth/` directory, with matching JSON metadata. IDs:
`lite-keyboard`, `lite-touchpad`, `lite-media`, `lite-shortcuts`,
`lite-chatgpt-shortcuts`, `lite-chrome-shortcuts`, `lite-shortcut-editor`,
`lite-host-picker`, `lite-keyboard-landscape`, and
`lite-bluetooth-permission-error`. They are Flutter widget renders and do not
claim physical Bluetooth host/device acceptance. A single product screenshot
index can include them alongside Full, Desktop and Web captures.
