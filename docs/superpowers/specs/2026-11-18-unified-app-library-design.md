# Unified App library

## User requirements

An App is the unit of discovery and installation: its icon and shortcut libraries travel together. Each App has macOS and Windows/Linux variants where supported. System-bound Apps expose only their supported systems (Safari and Finder are macOS only). The online platform lists Apps with their libraries. Existing twelve-key landscape UI and Bluetooth launch configuration remain unchanged.

## Data and compatibility

Keep the existing icon catalog and PNG provenance/hashes stable. Add `packages/app_library/catalog.json` as the App-library registry referencing canonical icon IDs. Public library schema version 1 contains Apps with `id`, `iconId`, `name`, `aliases`, `bundled`, `supportedOS`, and `libraries`. A library has `id`, `family` (`macos` or `windowsLinux`), `supportedOS` (`macos`, `windows`, `linux`), `version`, `sourceUrls`, and up to twelve actions. An action has `id`, `title`, `keys` and `requiresConfiguration`. Keys contain normalized modifiers (`CTRL`, `ALT`, `SHIFT`, `META`) followed by exactly one supported key. Unassigned actions have empty keys and require configuration. Do not infer real shortcut bindings from Ctrl/Command substitution. Record official provenance and use explicit unassigned actions for undocumented or user-defined shortcuts.

Canonical App identity is separate from installed application IDs and private launch bindings. The legacy artwork alias `codex -> chatgpt` must never merge the two products' shortcut libraries. Supported OS is explicit; sharing a Windows/Linux keyboard family does not advertise Linux availability. Existing profiles and custom bindings are preserved without guessing identity from display names.

## Runtime API

Generate the same dependency-light Dart model/data into Full, Desktop and independent Lite. Model interface: `AppLibraryCatalog.builtin` (all registered entries available for Full/Desktop; Lite filters `bundled`), `.apps`, `.appById(String)`, and strict `.fromJson(Map<String,dynamic>)`; `AppLibraryApp` fields described above, `.libraryForOS(String)`; `AppShortcutLibrary` fields above; `AppLibraryAction` fields above with `.isConfigured`. Implementers may add compatible helpers but coordinate changes before consumers use them. Files: `lib/app_library/app_library.dart`, `desktop_companion/lib/app_library/app_library.dart`, `apps/bluetooth/lib/app_library/app_library.dart`. These files are generated from one shared source/template. A bundle JSON envelope contains `schemaVersion:1`, `app` (one validated registry App), and `icon` (`id`, `sha256`, `pngBase64`). Bundle icon identity/hash must match the App and catalog. Bundle total size is bounded, and package parsing is non-executing.

The public action format permits only single keyboard chords and explicit unassigned actions, not shell commands, file paths, macros, native launch, voice, KVM, or installed application IDs. Public validation must not reuse permissive private account-backup validation.

## Full and Desktop

Desktop owns configuration. Its App library supports OS preview and atomic icon/profile installation for the current host OS. Add-copy is the default; replacing an existing profile is explicit. Optional source metadata on RemoteProfile carries catalog App ID/library ID/version without changing legacy ProfileConfig backup encoding. Known managed Apps retain foreground and launch protections; unknown Apps can use explicitly installed manual keyboard profiles without turning installed launch-only targets into managed input targets. Full phone browses/previews the library, receives Desktop-created profiles, and explains that installation happens on Desktop. It must not add implicit phone-to-Desktop configuration writes.

## Lite

Lite remains offline and Bluetooth only. Show the same App-library association for bundled entries; choose the controlled computer OS explicitly. Installation persists the icon association and local shortcut profile together. Unassigned actions are visible and configurable but send no HID input. Existing consumer/media shortcuts remain supported. Import must neither create nor overwrite private app-launch chords. No network, KVM or voice features are added.

## Online platform

Add immutable registered App catalogs and bundle download routes under `/v1/apps/`, using Git-reviewed publications. Web cards expose OS availability, action previews, provenance and bundle downloads. Preserve `/v1/icons/` compatibility. Reject unsupported actions, duplicate IDs, mismatched OS/family, bad icon hashes, oversize packages and malformed encodings. No submission/admin system or new public deployment is assumed. Public deployment awaits an actual supplied target.

## Acceptance

Validate catalog/model generation reproducibly, all App-to-icon associations, Safari filtering, OS-family distinctions, strict public payload rejection, offline Lite install and unassigned input behavior, preserved launch bindings/custom profiles, Desktop installation and manifest synchronization, browser catalog/download behavior and legacy icon endpoints. Run affected suites and platform builds; inspect packaged runtime, then install signed upgrades on the currently authorized PC and phone. Commit/push the feature and merge passing work into main. Preserve signing identity and local data. Planned versions: Full/Desktop 1.8.0+10 and Lite 1.3.0+4.
