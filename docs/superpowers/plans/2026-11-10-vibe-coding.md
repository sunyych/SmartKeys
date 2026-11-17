# Vibe Coding Implementation Plan

**Goal** Add a Vibe Coding home panel with Codex, Claude and Cursor app switching, project selection, shortcuts and independent local dictation controls.

**Architecture** The phone renders Desktop-owned `vibe.codex`, `vibe.claude` and `vibe.cursor` layouts. The companion resolves installed app IDs and checks the live foreground app before executing Vibe keyboard actions. The panel shares the existing phone dictation entry and recognizer lifecycle.

**Tech stack** Flutter, Dart, the existing companion manifest and authenticated LAN transport.

**Spec** The confirmed interaction in this chat, with Claude Desktop Code as the Claude target.

**Editing reference** [Vibe Shortcut](https://github.com/Scott-Du/vibe-shortcut) at `dfd5c8805bbd6ba6429c1f1695895aca4611d516`. Use the sending, deletion, clipboard, punctuation and screenshot actions with the existing local voice controls.

## Desktop and protocol

- [x] Extend `packages/lumiakeys_protocol/lib/lumiakeys_protocol.dart` with Desktop-owned app/layout defaults. Add missing built-ins to old manifests without overwriting edits. Use separate `vibe.<appId>` layouts and stable `vibe.<appId>.<action>` button IDs.
- [x] Update `desktop_companion/lib/desktop_controller.dart` and `desktop_actions.dart` for Claude/Cursor discovery, launching or focusing, and foreground checks for Vibe actions. Preserve Desktop-managed editable project bindings and show a setup hint for unassigned actions. Keep legacy shortcut layouts and requests compatible.
- [x] Add the reference editing keys to each Vibe layout. Send the alternate Enter chord on hold and repeat Backspace while held. Constrain delete-to-start to the current line. Use fixed punctuation IDs and the OS region screenshot picker to keep text and launch data on Desktop.
- [x] Run protocol and companion tests for migration, checked target routing, disabled actions and supported bindings.

## Mobile

- [x] Add a standalone Home tab in `lib/ui/home_screen.dart` before Custom, or next to General when Custom is hidden. Render the three app choices, selected app controls and connection/setup states. Route app and button IDs through `AppController` and the current companion service.
- [x] Expose Start and Stop through the same `LocalDictationEntryButton` session in `lib/ui/local_dictation_panel.dart`. Stop uses the existing finish/cancel lifecycle, including startup and route disposal.
- [x] Run mobile widget tests for tab placement, app/shortcut routing and distinct voice controls. Run Flutter analysis and the affected suites, and review the combined diff.
