# LumiaKey functional guides

The Chinese and English guides cover the mobile/tablet app and LumiaKey Desktop
at version **1.3.0+5**. The reviewed product source is commit
`2469b3af6b2abad6a5ff5a8976d83e33f8ae0a04`, dated for this documentation review on
2026-10-28 in America/Los_Angeles.

- [中文软件功能说明书](LumiaKey_Functional_Guide_ZH.docx)
- [English functional guide](LumiaKey_Functional_Guide_EN.docx)

Each guide includes 20 screenshots and the same functional coverage. The app UI
is primarily English; the Chinese guide retains visible English control names.

## Screenshot provenance

The images in `screenshots/` are captures of actual Flutter widget rendering,
not redrawn mockups and not physical-device captures. Hardware, network,
installed-app, recognition-model and usage states are test fixtures. In
particular, an installed/ready model indicator does not establish that a real
model was downloaded, nor that speech recognition or native text insertion was
accepted on a device. Installer version/hash/size details are test data, not
published release metadata.

`screenshot_manifest.json` records the source test, viewport, original sidecar,
reviewed source commit and SHA-256 of each retained image. The curated home and
tablet captures use the shipped `assets/profiles/` templates. Apps and Codex use
the real HomeScreen with a fixture Desktop manifest. Other page captures use
the existing screenshot suites and their example configuration.

## Rebuild screenshots

From the repository root, set `SMARTKEYS_SCREENSHOT_DIR` to an absolute output
folder and run these existing or documentation-specific suites in sequence:

```powershell
$env:SMARTKEYS_SCREENSHOT_DIR = Join-Path $PWD 'build/manual-screenshots'
$env:SMARTKEYS_SCREENSHOT_FONT = 'C:\Windows\Fonts\msyh.ttc'
$env:SMARTKEYS_SCREENSHOT_SYMBOL_FONT = 'C:\Windows\Fonts\seguisym.ttf'
flutter test --no-pub test/ui_screenshot_test.dart
flutter test --no-pub test/usage_dashboard_screen_test.dart test/community_setup_screen_test.dart
flutter test --no-pub test/desktop_installer_screenshot_test.dart
flutter test --no-pub test/manual_screenshot_test.dart
Push-Location desktop_companion
flutter test --no-pub test/ui_screenshot_test.dart
Pop-Location
```

Copy the images referenced by `manual_content.json` and refresh their manifest
before regenerating the guides. Keep private connection codes out of captures.
The font paths above are for this Windows capture environment; choose equivalent
CJK and symbol fonts on other systems. These test font overrides keep Chinese
language names and keyboard symbols readable without changing product assets.

## Rebuild documents

`manual_content.json` is the shared bilingual content source.
`scripts/build_feature_manuals.py` uses Python with `python-docx` and Pillow:

```powershell
python scripts/build_feature_manuals.py
```

Use the Codex bundled Python when working in Codex. The script writes the two
DOCX files in this folder. Render both documents and inspect **every page**
after any content, image, font or layout change. Rendering outputs and test logs
belong in ignored `build/manual-qa/`, not in the deliverable directory.

## Source references

- [Project overview](../../README.md)
- [Tablet support](../TABLET_SUPPORT.md)
- [Usage and sharing](../SHORTCUT_USAGE.md)
- [Google account backup](../GOOGLE_BACKUP.md)
- [Local dictation](../../README.md#local-quick-dictation)
- [UI review findings](UI_REVIEW.md)

These guides describe implementation and UI states. They do not replace
Android HID hardware acceptance, live speech quality/latency checks, native
Windows/macOS permissions and insertion checks, or signed iPad installation
and physical-device testing.
