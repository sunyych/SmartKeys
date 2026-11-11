# Computer Modes Implementation Plan

**Goal** Give Android a Bluetooth-only mode and give Android and iOS a Desktop mode, with one application row and settings saved separately for each computer.

**Architecture** An active Desktop connection takes precedence over Android Bluetooth. The phone stores selected app IDs and Bluetooth keyboard bindings in its local configuration. The Desktop manifest supplies managed apps and shortcuts. Advanced mode uses the installed-app manifest without requiring Bluetooth setup. On iOS the pairing screen gates the controls until Desktop is ready.

**Tech stack** Flutter, the Android HID transport, and the existing Desktop companion protocol.

**Spec** The requested two-mode flow and the confirmed voice behavior. In Bluetooth mode the two voice actions send the corresponding configured computer shortcuts. Advanced mode retains separate LumiaKey local dictation Start and Stop.

- [x] Define the computer modes, app catalogue, validated keyboard chords, and per-computer storage in `lib/models/computer_setup.dart`, `lib/models/config.dart` and `lib/controllers/app_controller.dart`. Route Bluetooth chords only while the saved computer is still active. Cover host changes, JSON compatibility, and mode priority in controller tests.
- [x] Build the first-connection and edit wizard in `lib/ui/computer_setup_wizard.dart`. Let users choose apps, configure and try the global launch chord and app actions on Android, and save only valid settings for the active computer. Desktop uses its detected apps and managed bindings.
- [x] Integrate the app row and mode-specific surfaces in `lib/ui/home_screen.dart` and `lib/ui/vibe_coding_panel.dart`. Use one Vibe Coding entry, choose the app in the top row, and block iOS controls when Desktop is disconnected. Verify portrait/landscape, app selection, launch, Bluetooth actions, and transition to Desktop.
- [x] Supply Desktop-managed browser and meeting apps and bindings in `packages/lumiakeys_protocol` and `desktop_companion`. Use a persisted Desktop identity to recognize the same computer after restart. Check starter migration, platform-specific bindings and target routing.
- [x] Run Flutter analysis, mobile, protocol and Desktop tests. Build and install the new Android APK on the connected Moto G Play, verify its checksum, and confirm a cold launch.
