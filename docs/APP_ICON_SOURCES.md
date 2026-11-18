# Application icon sources and limits

The active catalog has **16 application/brand resources and 17 compatible IDs**. `codex` is the historical ChatGPT wire alias, not another brand or another artwork. Native installed-app icons take priority; bundled PNGs provide an offline fallback and the same allowlisted IDs can be downloaded from the existing Rust dashboard service. Unknown IDs never become an arbitrary URL proxy.

All active offline PNGs are byte-identical in `assets/app_icons`, `desktop_companion/assets/app_icons`, and `community_server/assets/app_icons`. `registered_sources.json` records source URLs, hashes, dimensions, file sizes, alias semantics and the provenance boundary. Current assets are at most 256 pixels and 64 KiB. Companion native icon responses additionally require valid decoded PNG data and at most 512 pixels in each dimension.

## Active resources

| ID | PNG | Registered source | Provenance |
| --- | --- | --- | --- |
| `chatgpt` | `openai.png` | [source](https://cdn.simpleicons.org/openai) | inherited PNG; source attribution inherited, not revalidated |
| `chrome` | `chrome.png` | [source](https://cdn.simpleicons.org/googlechrome) | inherited PNG; source attribution inherited, not revalidated |
| `vscode` | `vscode.png` | [source](https://cdn.simpleicons.org/visualstudiocode) | inherited PNG; source attribution inherited, not revalidated |
| `photoshop` | `photoshop.png` | [source](https://cdn.simpleicons.org/adobephotoshop) | inherited PNG; source attribution inherited, not revalidated |
| `illustrator` | `illustrator.png` | [source](https://cdn.simpleicons.org/adobeillustrator) | inherited PNG; source attribution inherited, not revalidated |
| `premiere` | `premiere.png` | [source](https://cdn.simpleicons.org/adobepremierepro) | inherited PNG; source attribution inherited, not revalidated |
| `claude` | `claude-app.png` | [source](https://cdn.simpleicons.org/claude) | downloaded Claude SVG; rasterized original artwork |
| `cursor` | `cursor.png` | [source](https://cdn.simpleicons.org/cursor) | WIP supplied SVG; rasterized original artwork |
| `firefox` | `firefox.png` | [source](https://cdn.simpleicons.org/firefoxbrowser) | WIP supplied SVG; rasterized original artwork |
| `safari` | `safari.png` | [source](https://cdn.simpleicons.org/safari) | WIP supplied SVG; rasterized original artwork |
| `zoom` | `zoom.png` | [source](https://cdn.simpleicons.org/zoom) | WIP supplied SVG; rasterized original artwork |
| `appleMusic` | `appleMusic.png` | [source](https://cdn.simpleicons.org/applemusic) | WIP supplied SVG; rasterized original artwork |
| `teams` | `teams.png` | [source](https://cdn-dynmedia-1.microsoft.com/is/content/microsoftcorp/Teams-Icon-FY26) | Microsoft 365 official FY26 artwork; rasterized SVG |
| `edge` | `edge.png` | [source](https://edgecdn-embza6g8cacagcbn.z01.azurefd.net/welcome/static/favicon.png) | Edge official website favicon; PNG normalized |
| `finder` | `finder.png` | [source](https://ipcdn-web.apple.com/assets/v2/web/f2ab6839-b5a7-45f8-bcb3-037aa7887965) | Apple support Finder icon; PNG normalized |
| `solidworks` | `solidworks-app.png` | [source](https://help.solidworks.com/favicon.png) | official SOLIDWORKS Help favicon; 16px fallback, not native application artwork |

## Rights and historical assets

Simple Icons licenses its project data under CC0, but that does not grant permission to redistribute every brand mark or use another party's trademarks. See the [project disclaimer](https://github.com/simple-icons/simple-icons/blob/develop/DISCLAIMER.md). No brand-artwork redistribution permission is established by this catalog. Microsoft, Apple, Adobe, Mozilla, OpenAI, Anthropic, Cursor, Zoom and Dassault Systemes retain their respective rights. This source record describes provenance; it does not claim brand endorsement or a new license.

The original seven PNGs were retained without overwriting their bytes. Six remain active and have inherited source attribution; their original download history and individual permissions were not independently verified in this handoff. The original `solidworks.png` referred to the Dassault Systemes corporate mark and is **not** registered as the SOLIDWORKS fallback. The active `solidworks-app.png` is the product-help site's small favicon, so native extraction remains preferable for high-resolution application artwork.

The WIP `claude.svg` identifies Anthropic's corporate wordmark. It remains historical source material and is never registered or rasterized as the Claude application icon. The active `claude-app.svg` was downloaded from the separately registered Claude entry. The vector conversion tool uses a fixed allowlist and preserves original shapes; it does not synthesize logos.

Official page provenance: [Finder support](https://support.apple.com/en-by/guide/mac-help/mchlp2605/mac), [Microsoft 365 Teams artwork](https://www.microsoft.com/en-us/microsoft-365), [Microsoft Edge](https://explore.microsoft.com/en-us/edge/), [SOLIDWORKS Help](https://help.solidworks.com/).

## Validation and runtime behavior

Native extraction is limited to the registered application IDs and bounded metadata. Windows uses a fixed PowerShell script with an explicit scoped parameter; the process is killed on timeout. macOS uses NSWorkspace; Linux reads bounded matching `.desktop` metadata and local PNG theme files. Native results are validated before caching (five minutes for a valid icon, thirty seconds for a miss); simultaneous requests share one extraction. Icon failure is optional and never blocks shortcut execution.

The companion `/icons/{appId}` resource requires the existing pairing token, enabled app sync, enabled icon sync and a detected app. It returns a PNG content type, a content hash ETag, private cache policy and `nosniff`; unknown, disabled and failed icons return 404. The central dashboard serves its fixed registered resources with accurate MIME types and does not fetch client-supplied URLs.

Linux input is explicitly X11-only. Pointer capability is advertised only after a successful xdotool query (or a deliberately injected implementation). Wayland and missing displays remain unsupported. Parsing tools run with a fixed C locale. Fixed punctuation actions use xdotool after foreground validation; region screenshots and native dictation are not advertised as implemented Linux actions. This is a source/runtime boundary, not physical Linux acceptance evidence.

Linux runtime tools are `xdotool` for X11 input, `pactl` for PulseAudio/PipeWire volume, `playerctl` for an active MPRIS media player, and `brightnessctl` for the existing Dark brightness toggle. Dark requests 1% brightness and restores 100%; it requires a supported backlight device and permission to change it. It does not change the desktop theme. Missing tools, unavailable players or backlight permissions report an error. CI uses a virtual PulseAudio sink for the real locale check; brightness assertions use a recording runner and never change a runner's display.

Linux artifacts use an Ubuntu 24.04 x86_64 build environment and the runtime dependencies above. Input automation requires an X11 session; compatibility on other distributions requires separate validation.
