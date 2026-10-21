# Tablet controls and iPad

LumiaKey adapts its controls to the current app window. It supports Android
tablets through the existing Bluetooth HID connection and iPad through
LumiaKey Desktop on a local Wi-Fi network.

## Choose the control surface

In **Settings → Control Surface**, select **Automatic**, **Phone controls**, or
**Shortcut board**.

- **Automatic** uses the shortcut board when the window's shortest side is at
  least 600 logical pixels. A smaller window, including a narrow split view,
  uses the phone controls.
- **Phone controls** keeps the existing phone layout regardless of window
  size.
- **Shortcut board** shows the keyboard-only layout regardless of window
  size. The wheel and mouse pad do not take up board space.

Automatic mode looks at the available window dimensions, not the model name of
the device. Split view can therefore change the selected layout while the app
is open.

## Pages and existing profiles

Choose any whole number from **24** through **60** keys per board page in
Settings; 24, 40, and 60 are presets, and new installs use 40. The same value
is stored in `AppConfig.preferences.tabletKeysPerPage` and can be set in
configuration JSON. For example:

```json
{
  "preferences": {
    "controlSurfaceLayout": "shortcutBoard",
    "tabletKeysPerPage": 48
  }
}
```

Use the page controls to move between banks. Local Profiles can store positions
0 through 59, so every key remains available as you move between pages.

Existing Profiles with 15 keys keep their original buttons and layout. New
positions are created when you edit an unused board slot, and profile JSON
import/export preserves positions through 59. Phone controls display up to 15
keys in a bank, preserving the established 3 × 5 portrait and 5 × 3 landscape
arrangements. Desktop-managed layouts use the same page capacity and banking.

## Connect an iPad to Desktop

The iPad uses LumiaKey Desktop for supported keyboard shortcuts and recognized
text output. Android continues to send direct keyboard and media input through
Bluetooth HID.

1. Connect the iPad and the computer to the same trusted Wi-Fi network.
2. In LumiaKey Desktop, open the **Connect an iPad** panel and select **Copy
   iPad connection code**.
3. On iPad, open LumiaKey **Settings → Desktop Companion**. Paste the code in
   **Desktop connection code**, then select **Connect**.
4. Allow Local Network access if iPadOS requests it.

The code contains Desktop's local IPv4 address, temporary port, and session
token. Desktop lists its private IPv4 addresses so you can choose the one on
the Wi-Fi network reachable by the iPad, avoiding VPN and virtual adapters.
Treat the complete code like a password. LumiaKey keeps the token in
memory and sends it in the authentication header for local HTTP requests. The
connection is authenticated but not encrypted; use a network you trust and do
not post or send the code to others. If the session expires, copy a fresh code
from Desktop and connect again.

Speech recognition remains local to the iPad. LumiaKey sends the recognized
text to Desktop for insertion into a supported focused app. The iPad route does
not provide Android Bluetooth HID behavior for held keys or mouse input;
unsupported actions report an error.

## Build and acceptance

An unsigned native iPad build requires macOS with Xcode. [Mac CI run 39519873752](https://github.com/sunyych/SmartKeys/actions/runs/39519873752)
completed successfully, including the unsigned debug build with Flutter 3.44.2
that validates native compilation and plugin linkage. The iOS target's minimum
deployment version is iOS 13.0. Signing and installing on a physical iPad
additionally require an Apple signing identity and a connected, appropriately
provisioned device. Unsigned CI does not validate signing, installation, or
physical input; those steps remain unverified.

Automated tablet screenshots and their HTML index are local validation output,
kept in ignored build/output directories. They show Flutter widget rendering
and do not establish native iPad installation or physical-device acceptance.
