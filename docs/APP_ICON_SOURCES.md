# LumiaKeys application icon sources

The offline icons in `assets/app_icons/` were downloaded on 2026-07-19 from
the [Simple Icons](https://simpleicons.org/) CDN and rasterized to transparent
256 × 256 PNG files for the Android client. Simple Icons' project license is
CC0, but this does not establish that every included brand icon is CC0. Check
the individual icon entry and the brand's terms before redistribution or
commercial use. Product names and logos remain trademarks of their owners.

| LumiaKeys app ID | Simple Icons slug | Local asset |
| --- | --- | --- |
| `codex` | `openai` | `openai.png` |
| `chrome` | `googlechrome` | `chrome.png` |
| `vscode` | `visualstudiocode` | `vscode.png` |
| `photoshop` | `adobephotoshop` | `photoshop.png` |
| `illustrator` | `adobeillustrator` | `illustrator.png` |
| `premiere` | `adobepremierepro` | `premiere.png` |
| `solidworks` | `dassaultsystemes` | `solidworks.png` |

These assets identify installed applications; they do not imply endorsement or
affiliation.

The community server keeps byte-identical copies under
`community_server/assets/app_icons/` so its container build is self-contained.
Its catalog is an allowlist and serves only those files; it never fetches a
client-supplied URL. See the [Simple Icons disclaimer](https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md)
for the distinction between the project's license and per-icon rights.
