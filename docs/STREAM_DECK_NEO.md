# Stream Deck Neo research and LumiaKey integration

## Product and SDK routes

Elgato lists Stream Deck software support for macOS 13 and Windows 11 in its [compatibility guide](https://help.elgato.com/hc/en-us/articles/34512594204049). Elgato’s plugin SDK runs inside the host Stream Deck application; see its [plugin environment](https://docs.elgato.com/streamdeck/sdk/introduction/plugin-environment/). Neo Infobar plugin support starts with SDK 3.0 and Stream Deck 7.6, and is display-only for the information strip; see the [Neo Infobar guide](https://docs.elgato.com/streamdeck/sdk/guides/neo-infobar/).

Elgato also documents direct device communication in its [Stream Deck Neo HID reference](https://docs.elgato.com/streamdeck/hid/stream-deck-neo/), including 96 × 96 key areas, a 248 × 58 Infobar, additional button/sensor inputs, and the device’s JPEG rotation convention. This project does not claim that the Neo lacks a public USB interface.

## LumiaKey route

LumiaKey already has a Windows/macOS Flutter companion with tray lifecycle, managed app discovery, persisted desktop preferences, platform control channels, and a screenshot gallery. The launcher is added as its eighth navigation section and as an **Open Launcher** tray action. It reuses `DesktopController`, `DesktopActions`, and the managed application catalog. The eight slot IDs live in desktop-only preferences and are not added to the phone-synced manifest. Branded PNG assets already present in the repository provide recognizable icons for VS Code, SolidWorks, Premiere, Photoshop, OpenAI/Codex, Illustrator, and Chrome; other managed apps fall back to their configured icon symbol.

The launcher controls media playback with the macOS system media event / Windows media-key event. Mute reads and toggles the actual default output mute state using macOS volume scripting and the Windows Core Audio endpoint interface.

## Reusable source references

- `desktop_companion/lib/desktop_controller.dart`: local launcher slot persistence and managed-app launch routing.
- `desktop_companion/lib/desktop_ui.dart`: responsive eight-key launcher, clock, app editor and system controls.
- `desktop_companion/macos/Runner/MainFlutterWindow.swift` and `desktop_companion/windows/runner/flutter_window.cpp`: platform controls.
- `desktop_companion/test/ui_screenshot_test.dart`: normal/narrow/minimum launcher, editor, and error screenshots.
- `scripts/generate_screenshot_index.dart`: current screenshot gallery generation.
