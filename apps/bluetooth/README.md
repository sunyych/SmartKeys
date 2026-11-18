# LumiaKey Bluetooth Lite

An independent Android 9+ Bluetooth HID app with local keyboard, mouse, media and editable shortcuts. It has no Internet or microphone permission, account service, companion connection, icon download or diagnostics upload.

Version **1.2.0+3** matches Full's landscape control surface: top LumiaKey brand,
left Launchpad/General/application rail, twelve keys in four columns and three
rows, top Bluetooth-host/clock/media controls, and a right touchpad. There is no
KVM or voice-input UI. Bluetooth device management stays in local settings.

Launchpad has twelve local slots. Tap an unconfigured slot or edit it in Settings
to enter its name, offline icon, optional shortcut profile and keyboard launch
combination. Set the corresponding launch shortcut on your computer as well
(for example, an operating-system app shortcut or pinned-app hotkey). Only a
saved, valid binding and an active Bluetooth connection enable sending it.
The application sends that exact keyboard combination and cannot confirm which
computer window opened. Selecting a profile in the left rail changes the local
shortcut page without starting an application.

Existing profiles and their full shortcut lists are retained. New defaults have
twelve keys; longer saved profiles use twelve-key pages. Settings can add/edit
keyboard combinations and media actions. Failed saves preserve the previous
configuration. Input is bound to a captured Bluetooth host and a resumed control
context; queued input is cancelled when the host, page or lifecycle changes.

The icon library bundles fifty original application icons, searchable by name, ID or alias without a network request. Source and terms references can be viewed as text offline. Icons do not grant application-launch or command permissions.

Error logs accept only fixed categories from the contained, dependency-free diagnostics package. They never retain raw exception text, stacks, key combinations, input content, host names/addresses or tokens. Version/build metadata comes from Android PackageManager; unavailable metadata is explicitly unverified and remains local. Flutter and platform failures preserve existing error handling while recording only a fixed code.

Logs default to 30 days with a 7-day option, at most 1000 records and 5 MiB. Expiry is pruned and persisted at startup, when opening the log, on writes and hourly while the process is running. Disposal cancels the cleanup timer. Storage failures keep the bounded in-memory view and show a local persistence error; the logger never recursively logs its own failure. Clearing is local and never sends a request.

Run `python scripts/check_isolation.py`, `flutter analyze`, and `flutter test` from this directory. The isolation checker also accepts `--apk <path>` to validate real package permissions, forbidden components and the bytes of all fifty bundled icon assets. This project depends only on its contained `packages/diagnostics_core` path, Flutter and shared preferences; it can be copied and built independently of the Full repository.

Actual APK checks also inspect every packaged release AOT library (or the debug
kernel) for current Lite surface markers. Version numbers and new image assets
alone do not establish that the latest code was packaged. Use a clean build
directory when replacing old Gradle JNI merge outputs.
