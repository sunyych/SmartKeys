# Functional guide validation

Review date: 2026-10-28 (America/Los_Angeles).
Reviewed product version: 1.3.0+5.
Reviewed product commit: `2469b3af6b2abad6a5ff5a8976d83e33f8ae0a04`.

## Content and captures

The Chinese and English documents cover the same mobile/tablet and Desktop
features. Each contains 20 embedded screenshots. Both versions explain that
the captures render real Flutter widgets with fixture device/network state,
and distinguish interface language from recognition language.

The following scoped suites passed, for a total of 24 tests:

| Suite | Tests |
| --- | ---: |
| `test/ui_screenshot_test.dart` | 7 |
| `test/usage_dashboard_screen_test.dart` | 7 |
| `test/community_setup_screen_test.dart` | 7 |
| `test/desktop_installer_screenshot_test.dart` | 1 |
| `desktop_companion/test/ui_screenshot_test.dart` | 1 |
| `test/manual_screenshot_test.dart` | 1 |

The added documentation capture loads shipped Profile templates and uses the
actual HomeScreen. Its Apps capture waits for brand image decoding and asserts
that the three displayed application icons have non-null decoded images.
Captures use a CJK text font and a symbol fallback so Chinese language names
and keyboard symbols are readable. Retained PNG hashes match the screenshot
manifest.

## Document checks

- Each document has 13 pages, 13 document/section headings and 20 embedded images.
- Both DOCX ZIP integrity checks pass.
- The generator passes Python syntax compilation; `git diff --check` passes.
- All 26 pages were rendered and inspected at full image size. A crowded
  Chinese figure caption was shortened, and spacing was added between the
  comparison table and its screenshot. The final render was checked again.
- The packaged `render_docx.py` was attempted. This Windows bundle does not
  provide LibreOffice, and the renderer reports `soffice.exe` unavailable.
  Final layout verification therefore used Microsoft Word 16 to open the
  generated DOCX files read-only and export temporary PDFs, followed by the
  bundled Poppler rasterizer at 120 dpi. The final artifacts remain DOCX.

Temporary PDFs, page PNGs and test logs are under ignored `build/manual-qa/`.
Product behavior was not modified. UI wording findings and suggested changes
are recorded separately in [UI_REVIEW.md](UI_REVIEW.md).

## Acceptance boundary

This work validates the documented implementation and rendered example states.
It does not validate physical Android HID transmission, real-model speech
accuracy or latency, operating-system microphone/injection permissions,
target-app input, production community/OAuth deployment, or signed iPad
installation and physical-device use.

## PDF delivery update — 2026-10-29

The bilingual content and reviewed product source are unchanged. Each PDF
reader edition is 13 pages and contains 20 screenshots. The PDFs were produced
from the previous final Microsoft Word render; the DOCX files remain the
editable sources, while the PDFs are the reading and delivery versions.

Both delivered PDFs were re-rasterized with bundled Poppler at 120 dpi. SHA-256
comparisons confirmed that all 26 pages exactly match the existing, visually
reviewed `final-ZH` and `final-EN` page renders. PDF structure checks also
confirmed 13 pages and 20 embedded images per document. The product source
audit date above remains 2026-10-28.
