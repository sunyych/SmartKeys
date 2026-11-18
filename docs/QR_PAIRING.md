# Desktop QR pairing

1. Connect the phone and LumiaKey Desktop to the same Wi-Fi network.
2. In Desktop, open **General** and choose the reachable private Wi-Fi address. When Desktop is running, its pairing QR appears there.
3. On the phone, open **Pair Desktop** and choose **Scan Desktop QR code**. Point the camera at the QR. Scanning uses the same authenticated local connection flow as manual pairing; QR contents are never opened as links.
4. If scanning is unavailable or you prefer not to use the camera, paste the Desktop connection code and choose **Connect**. Treat the code like a password.

The pairing sheet adjusts for the software keyboard and can scroll the code field and buttons into view. Camera permission is used by the Regular mobile edition only when scanning starts. LumiaKey Lite removes the camera permission and does not offer Desktop pairing.

## Automated checks

From the repository root:

```sh
flutter test test/desktop_connection_panel_keyboard_test.dart test/desktop_connection_scanner_test.dart test/desktop_connection_panel_screenshot_test.dart
```

For the Desktop QR component and its synthetic-credential screenshot:

```sh
cd desktop_companion
flutter test test/desktop_pairing_qr_test.dart
```

The automated scanner UI uses injected fixtures and does not request camera access. Physical camera scanning and end-to-end phone-to-Desktop pairing still need device acceptance testing.
