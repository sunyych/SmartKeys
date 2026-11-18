# Application icon sources and limits

The authoritative registry is [`packages/app_icon_catalog/catalog.json`](../packages/app_icon_catalog/catalog.json). It contains **50 unique built-in applications and 10 server-only applications**, all with actual artwork. Aliases never add to those counts. The historical `codex` protocol/configuration value remains a separate ChatGPT compatibility adapter, and is not advertised as the Codex product or an ordinary search alias.

Each original source file and its SHA256, retrieval date, original dimensions, resulting PNG hash, source page, brand/usage terms and normalization are recorded in the registry. Originals live in `sources/`; the prepared PNGs live in `png/`. Generated copies are byte-identical across Full, Desktop and independent Lite for the fifty built-ins. The Rust server owns all sixty PNGs in its Docker build context.

All outputs are 256×256 RGBA PNG, with a 224-pixel contain box centered on a transparent canvas. Shapes, colors, aspect ratio and complete edges are retained. Chromium renders original SVG filters; PNG recompression is lossless. The sixty decoded outputs have distinct hashes, total 1,047,665 bytes, with a maximum of 59,023 bytes.

## Identity and provenance changes

- Microsoft `microsoft365` uses the official Apple listing **541164041**, bundle **com.microsoft.officemobile**, version **2.116.1**: the former Office/Microsoft 365 application, now listed as Microsoft Copilot. It is distinct from standalone consumer Copilot listing 6472538445. Office-related aliases remain available.
- Windows Explorer is the actual 256-pixel application resource extracted read-only from installed Windows `explorer.exe`, icon 0. Registry provenance includes OS version, binary version/hash and extracted-resource hash. `sourceUrl` accurately uses `native-resource:`; its separately recorded HTTPS Microsoft support page is the clickable source link. No system application was modified.
- SOLIDWORKS uses the complete transparent horizontal product logo in the official SOLIDWORKS education logo package, retaining its 1397×444 proportions. It replaces the prior 16-pixel favicon and the unrelated Dassault corporate mark.
- Claude uses current official Claude website artwork; GitHub Desktop uses the official Desktop repository application icon, rather than substituting the GitHub corporate website favicon.
- Brave replaces the planned FileZilla **web-only** example because the official FileZilla website and SVN asset endpoints returned HTTP403. The required fifty built-in IDs remain unchanged.

## Rights boundary

Source availability and a project open-source license do not grant blanket redistribution or trademark rights for brand artwork. Every record links the relevant owner terms; no brand endorsement, partnership or separate permission is claimed. Some owner policies require written permission for particular logo uses. The registry reports provenance and does not establish that such permission has been obtained. Third-party images are not relicensed by this repository's code license.

## Registered resources

| App ID | Product | Delivery | Official source page | Owner terms | Retrieved |
| --- | --- | --- | --- | --- | --- |
| `chrome` | Google Chrome | Built-in | [source](https://www.google.com/chrome/) | [terms](https://www.google.com/permissions/) | 2026-11-17 |
| `cursor` | Cursor | Built-in | [source](https://cursor.com) | [terms](https://cursor.com/terms-of-service) | 2026-11-17 |
| `firefox` | Mozilla Firefox | Built-in | [source](https://www.mozilla.org/firefox/) | [terms](https://www.mozilla.org/en-US/foundation/trademarks/policy/) | 2026-11-17 |
| `teams` | Microsoft Teams | Built-in | [source](https://www.microsoft.com/en-us/microsoft-365/microsoft-teams) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `microsoft365` | Microsoft Copilot (Microsoft 365 / Office) | Built-in | [source](https://apps.apple.com/us/app/microsoft-copilot/id541164041) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `word` | Microsoft Word | Built-in | [source](https://www.microsoft.com/en-us/microsoft-365/word) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `excel` | Microsoft Excel | Built-in | [source](https://www.microsoft.com/en-us/microsoft-365/excel) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `powerpoint` | Microsoft PowerPoint | Built-in | [source](https://www.microsoft.com/en-us/microsoft-365/powerpoint) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `edge` | Microsoft Edge | Built-in | [source](https://www.microsoft.com/en-us/edge) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `zoom` | Zoom | Built-in | [source](https://www.zoom.com) | [terms](https://www.zoom.com/en/trust/legal-compliance/terms/) | 2026-11-17 |
| `photoshop` | Adobe Photoshop | Built-in | [source](https://www.adobe.com/products/photoshop.html) | [terms](https://www.adobe.com/legal/permissions/trademarks.html) | 2026-11-17 |
| `vscode` | Visual Studio Code | Built-in | [source](https://code.visualstudio.com) | [terms](https://code.visualstudio.com/brand) | 2026-11-17 |
| `chatgpt` | ChatGPT | Built-in | [source](https://chatgpt.com) | [terms](https://openai.com/brand/) | 2026-11-17 |
| `claude` | Claude | Built-in | [source](https://claude.ai) | [terms](https://www.anthropic.com/legal/trademark-guidelines) | 2026-11-17 |
| `safari` | Safari | Built-in | [source](https://apps.apple.com/us/app/safari/id1146562112) | [terms](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html) | 2026-11-17 |
| `finder` | Finder | Built-in | [source](https://support.apple.com/guide/mac-help/get-to-know-the-finder-mchlp2605/mac) | [terms](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html) | 2026-11-17 |
| `appleMusic` | Apple Music | Built-in | [source](https://apps.apple.com/us/app/apple-music/id1108187390) | [terms](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html) | 2026-11-17 |
| `illustrator` | Adobe Illustrator | Built-in | [source](https://www.adobe.com/products/illustrator.html) | [terms](https://www.adobe.com/legal/permissions/trademarks.html) | 2026-11-17 |
| `premiere` | Adobe Premiere Pro | Built-in | [source](https://www.adobe.com/products/premiere.html) | [terms](https://www.adobe.com/legal/permissions/trademarks.html) | 2026-11-17 |
| `solidworks` | SOLIDWORKS | Built-in | [source](https://files.solidworks.com/education/Download_SW_Logos/download_sw_logo.pdf) | [terms](https://www.3ds.com/legal-information) | 2026-11-17 |
| `aftereffects` | Adobe After Effects | Built-in | [source](https://www.adobe.com/products/aftereffects.html) | [terms](https://www.adobe.com/legal/permissions/trademarks.html) | 2026-11-17 |
| `acrobat` | Adobe Acrobat | Built-in | [source](https://www.adobe.com/acrobat.html) | [terms](https://www.adobe.com/legal/permissions/trademarks.html) | 2026-11-17 |
| `lightroom` | Adobe Lightroom | Built-in | [source](https://www.adobe.com/products/photoshop-lightroom.html) | [terms](https://www.adobe.com/legal/permissions/trademarks.html) | 2026-11-17 |
| `slack` | Slack | Built-in | [source](https://slack.com) | [terms](https://slack.com/media-kit) | 2026-11-17 |
| `discord` | Discord | Built-in | [source](https://discord.com/branding) | [terms](https://discord.com/branding) | 2026-11-17 |
| `telegram` | Telegram | Built-in | [source](https://telegram.org) | [terms](https://telegram.org/press) | 2026-11-17 |
| `whatsapp` | WhatsApp | Built-in | [source](https://www.whatsapp.com) | [terms](https://about.meta.com/brand/resources/whatsapp/whatsapp-brand/) | 2026-11-17 |
| `signal` | Signal | Built-in | [source](https://signal.org) | [terms](https://signal.org/legal/) | 2026-11-17 |
| `notion` | Notion | Built-in | [source](https://www.notion.com) | [terms](https://notion.notion.site/Notion-Trademark-Usage-Guidelines-9826313c686a4f6e9d8a48347162714b) | 2026-11-17 |
| `obsidian` | Obsidian | Built-in | [source](https://obsidian.md) | [terms](https://obsidian.md/brand) | 2026-11-17 |
| `evernote` | Evernote | Built-in | [source](https://evernote.com) | [terms](https://evernote.com/en-us/legal/trademark-use) | 2026-11-17 |
| `onenote` | Microsoft OneNote | Built-in | [source](https://www.microsoft.com/en-us/microsoft-365/onenote) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `outlook` | Microsoft Outlook | Built-in | [source](https://www.microsoft.com/en-us/microsoft-365/outlook) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `thunderbird` | Mozilla Thunderbird | Built-in | [source](https://www.thunderbird.net) | [terms](https://www.mozilla.org/en-US/foundation/trademarks/policy/) | 2026-11-17 |
| `spotify` | Spotify | Built-in | [source](https://open.spotify.com) | [terms](https://developer.spotify.com/documentation/design) | 2026-11-17 |
| `vlc` | VLC media player | Built-in | [source](https://www.videolan.org/vlc/) | [terms](https://www.videolan.org/legal.html) | 2026-11-17 |
| `obs` | OBS Studio | Built-in | [source](https://obsproject.com) | [terms](https://obsproject.com/forum/threads/forum-resource-and-ip-policy.178569/) | 2026-11-17 |
| `blender` | Blender | Built-in | [source](https://www.blender.org/about/logo/) | [terms](https://www.blender.org/about/logo/) | 2026-11-17 |
| `figma` | Figma | Built-in | [source](https://www.figma.com) | [terms](https://www.figma.com/using-the-figma-brand/) | 2026-11-17 |
| `sketch` | Sketch | Built-in | [source](https://www.sketch.com) | [terms](https://www.sketch.com/about-us/#press) | 2026-11-17 |
| `canva` | Canva | Built-in | [source](https://www.canva.com) | [terms](https://www.canva.com/policies/trademark-policy/) | 2026-11-17 |
| `github-desktop` | GitHub Desktop | Built-in | [source](https://desktop.github.com) | [terms](https://docs.github.com/en/site-policy/other-site-policies/github-logo-policy) | 2026-11-17 |
| `android-studio` | Android Studio | Built-in | [source](https://developer.android.com/studio) | [terms](https://developer.android.com/distribute/marketing-tools/brand-guidelines) | 2026-11-17 |
| `intellij-idea` | IntelliJ IDEA | Built-in | [source](https://www.jetbrains.com/company/brand/) | [terms](https://www.jetbrains.com/company/brand/) | 2026-11-17 |
| `pycharm` | PyCharm | Built-in | [source](https://www.jetbrains.com/company/brand/) | [terms](https://www.jetbrains.com/company/brand/) | 2026-11-17 |
| `docker` | Docker Desktop | Built-in | [source](https://www.docker.com) | [terms](https://www.docker.com/legal/trademark-guidelines/) | 2026-11-17 |
| `postman` | Postman | Built-in | [source](https://www.postman.com) | [terms](https://www.postman.com/legal/logo-usage/) | 2026-11-17 |
| `windows-terminal` | Windows Terminal | Built-in | [source](https://github.com/microsoft/terminal) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `powershell` | PowerShell | Built-in | [source](https://github.com/PowerShell/PowerShell) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `windows-explorer` | Windows File Explorer | Built-in | [source](https://support.microsoft.com/en-us/windows/experience/storage-filemanagement/find-your-files-and-apps-in-windows) | [terms](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks) | 2026-11-17 |
| `gimp` | GIMP | Online only | [source](https://www.gimp.org) | [terms](https://www.gimp.org/about/COPYING) | 2026-11-17 |
| `inkscape` | Inkscape | Online only | [source](https://inkscape.org) | [terms](https://inkscape.org/about/branding/) | 2026-11-17 |
| `audacity` | Audacity | Online only | [source](https://www.audacityteam.org) | [terms](https://manual.audacityteam.org/man/faq_about_audacity.html) | 2026-11-17 |
| `bitwarden` | Bitwarden | Online only | [source](https://bitwarden.com) | [terms](https://github.com/bitwarden/server/blob/main/TRADEMARK_GUIDELINES.md) | 2026-11-17 |
| `1password` | 1Password | Online only | [source](https://1password.com) | [terms](https://1password.com/legal/terms-of-service) | 2026-11-17 |
| `brave` | Brave | Online only | [source](https://brave.com/brave-branding-assets/) | [terms](https://brave.com/brave-branding-assets/) | 2026-11-17 |
| `notepadplusplus` | Notepad++ | Online only | [source](https://notepad-plus-plus.org) | [terms](https://github.com/notepad-plus-plus/notepad-plus-plus/blob/master/LICENSE) | 2026-11-17 |
| `sublimetext` | Sublime Text | Online only | [source](https://www.sublimetext.com) | [terms](https://www.sublimetext.com/eula) | 2026-11-17 |
| `7zip` | 7-Zip | Online only | [source](https://www.7-zip.org) | [terms](https://www.7-zip.org/license.txt) | 2026-11-17 |
| `winrar` | WinRAR | Online only | [source](https://www.win-rar.com) | [terms](https://www.win-rar.com/winrarlicense.html?L=1) | 2026-11-17 |

## Verification and runtime boundaries

Run `python scripts/generate_app_icon_catalog.py --check` and `python -m unittest scripts/test_generate_app_icon_catalog.py`. The offline standard-library generator verifies original/output hashes, complete PNG chunks/CRC/decompressed data, RGBA dimensions, unique product/alias identities, unique output hashes and all four synchronized resource trees. It never downloads files. Clients validate PNG content and size before caching; native per-computer icons retain their existing priority and identity keys.

An icon ID is display metadata only. Neither this catalog nor the website expands Desktop application launch, native extraction, shortcut or command allowlists. Unknown resource IDs remain404; the service is not a URL proxy. Full can fetch registered extra icons from its configured central origin; independent Lite only consumes its bundled fifty and has no network functionality.

See the canonical package README for generation and source-update steps.
