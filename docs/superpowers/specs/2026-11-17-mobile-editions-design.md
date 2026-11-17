# LumiaKey Lite and Regular mobile editions

## Approved product scope

The user approved implementation on 2026-11-17 after clarifying the two editions and asked for delivery in this chat after ending voice. The unrelated `feature/mobile-launcher-and-editions` branch is no longer part of the task. It matched main when fetched and the merge reported already up to date.

### Lite

- Android only, with direct Bluetooth HID keyboard and mouse input; no Desktop discovery, pairing, manifest synchronization, application launching, or automatic foreground-app control.
- Preserve the existing control surface and its touchpad. Remove the mixed-mode application toolbar and computer/application setup requirements.
- Supply General, ChatGPT, and Chrome as local Bluetooth shortcut profiles. Selecting ChatGPT or Chrome changes the shortcuts sent to the user's focused computer application; it does not claim to launch or focus that application.
- Provide a clearly discoverable shortcut settings page on the phone, reusing existing profile/button editing and adding/importing profiles.
- Preserve saved local edits. Keep Lite storage and Android application identity separate from Regular so both can be installed.

### Regular

- Android and iOS, with Desktop as the source of application availability and executable shortcut configuration. No Bluetooth fallback or phone-owned executable shortcut editing.
- Landscape-only control surface on phones and tablets.
- Left vertical, scrollable navigation: Launchpad, General, ChatGPT, Chrome, then the remaining available Desktop applications.
- Center: four columns by three rows, twelve large buttons, using available height instead of forcing square keys. Launchpad uses this same twelve-cell geometry to launch/focus applications on the connected computer.
- Right: persistent touchpad and existing connection/computer switching, speech input, and settings controls above it.
- General explicitly uses the Desktop general keyboard layout, independent of the currently foreground application.
- Default application layouts select twelve useful existing actions. Preserve custom layouts, stable action IDs, and user edits; existing larger layouts remain reachable in twelve-key pages. More than twelve available applications can likewise use launcher pages.
- Launch, shortcut, dictation, and pointer interactions must target the selected connected Desktop; interrupted switching or connection loss must not send an action to a different computer.
- Show Desktop connection setup when disconnected and disable unavailable actions. Check mouse-control capability before accepting pointer interaction.

## Implementation approach

Keep a shared source tree and isolate products at the application entry point, transport injection, storage, and native build flavors. Main defaults to Regular; the Lite entry point and Android flavor produce the standalone Lite application. A Lite branch can carry Lite-default entry/build selection without duplicating the underlying implementation or creating a second repository.

Use a dedicated Regular home widget rather than expanding the existing large mixed-mode page. Retain the old page as the Lite control surface with explicit Lite behavior. Tests that exercise retained components must select them explicitly; injecting a controller must never silently bypass the production edition route.

## Validation and delivery

- Analyze shared protocol, mobile, and Desktop projects; run meaningful existing regressions and new edition/layout tests.
- Render the real Regular widget tree for a landscape phone and iPad, plus Lite, and inspect screenshots for geometry, truncation, and touchpad usability.
- Build both Android flavors locally when tooling allows. Configure main-push CI to build Android Regular/Lite and use the existing macOS workflow for an unsigned iOS build.
- A Windows host cannot establish iOS compilation or device acceptance by itself. Report CI results separately from signing and physical-device verification; do not imply App Store or TestFlight delivery.
- Review the full diff, commit the authorized changes, and push the applicable branches as requested by the user's AGENTS instructions.
