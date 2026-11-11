# LumiaKey functional guides

The Chinese and English guides cover the mobile app and LumiaKey Desktop at
version **1.3.0+5** with the computer modes update. The reviewed product source
is commit `d01db294eaefc2a104f972738398fc7411caf21f` as of 2026-11-10 in
America/Los_Angeles.

- [中文软件功能说明书 PDF](LumiaKey_Functional_Guide_ZH.pdf)
- [English functional guide PDF](LumiaKey_Functional_Guide_EN.pdf)

Both guides cover Bluetooth-only and Desktop advanced modes, first-connection
setup, iPhone/iPad pairing and Vibe Coding. The Chinese guide retains visible
English control names. The DOCX files in this folder are from the October edition.

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
tablet captures use the shipped `assets/profiles/` templates. The setup wizard,
app row, Vibe Coding screens and iOS pairing gate render the product widgets
with fixture services. The pairing field is empty.

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
flutter test --no-pub test/tablet_control_board_test.dart
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
python scripts/build_feature_manuals.py --output-dir build/manual-qa/source
```

Use the Codex bundled Python when working in Codex. Export the generated
documents to PDF and inspect **every page** after changes to the content,
images, fonts or layout. Put the final PDFs in `docs/manuals/` and keep
intermediate files and logs in ignored `build/manual-qa/`.

## Source references

- [Project overview](../../README.md)
- [Tablet support](../TABLET_SUPPORT.md)
- [Usage and sharing](../SHORTCUT_USAGE.md)
- [Google account backup](../GOOGLE_BACKUP.md)
- [Local dictation](../../README.md#local-quick-dictation)
- [October UI review](UI_REVIEW.md)

These guides describe implementation and UI states. They do not replace
Android HID hardware acceptance, live speech quality/latency checks, native
Windows/macOS permissions and insertion checks, or signed iPad installation
and physical-device testing.
