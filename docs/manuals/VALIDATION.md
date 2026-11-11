# Functional guide validation

The reviewed product is LumiaKey 1.3.0+5 at commit
`d01db294eaefc2a104f972738398fc7411caf21f`. The guide review took place on
2026-11-10 in America/Los_Angeles.

## Content and screenshots

Each reader PDF contains 17 pages and 25 screenshots. The Chinese and English
guides cover the same sections, including the two computer modes, app selection
and shortcut setup, iPhone/iPad pairing, the app row, and Vibe Coding. The guides
identify the launch and voice chords shown in the screenshots as examples.

| Flutter capture suites | Tests passed |
| --- | ---: |
| Mobile UI, usage, community, installers, and tablet pairing | 25 |
| Manual Home, setup, launch confirmation, and Vibe Coding | 1 |
| Desktop UI | 1 |

The screenshots render the current product widgets with fixture services. The
mobile pairing field is empty. The screenshot manifest records each source test,
rendered viewport, fixture notes and SHA-256. The retained PNGs match the
manifest and the bilingual content references.

## PDF checks

- Exported the reader editions from temporary documents and rendered all 34 PDF
  pages with Poppler at 120 dpi.
- Inspected the page renders in both languages. Checked that headings, captions,
  page numbers and screenshots fit and appear in the intended order.
- Verified each page's section heading, figure captions and embedded image count
  against `manual_content.json`. Verified the delivered file hashes against the
  reviewed exports.

The fixtures verify UI and documented behavior. Physical Bluetooth input,
iPhone/iPad installation and pairing, and speech recognition or text delivery
on a connected device require separate device checks.
