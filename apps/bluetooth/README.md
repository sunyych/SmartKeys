# LumiaKey Bluetooth Lite

An independent Android 9+ Bluetooth HID app with local keyboard, mouse, media and editable shortcuts. It has no Internet or microphone permission, account service, companion connection, icon download or diagnostics upload.

The icon library bundles fifty original application icons, searchable by name, ID or alias without a network request. Source and terms references can be viewed as text offline. Icons do not grant application-launch or command permissions.

Error logs accept only fixed categories from the contained, dependency-free diagnostics package. They never retain raw exception text, stacks, key combinations, input content, host names/addresses or tokens. Version/build metadata comes from Android PackageManager; unavailable metadata is explicitly unverified and remains local. Flutter and platform failures preserve existing error handling while recording only a fixed code.

Logs default to 30 days with a 7-day option, at most 1000 records and 5 MiB. Expiry is pruned and persisted at startup, when opening the log, on writes and hourly while the process is running. Disposal cancels the cleanup timer. Storage failures keep the bounded in-memory view and show a local persistence error; the logger never recursively logs its own failure. Clearing is local and never sends a request.

Run `python scripts/check_isolation.py`, `flutter analyze`, and `flutter test` from this directory. The isolation checker also accepts `--apk <path>` to validate real package permissions, forbidden components and the bytes of all fifty bundled icon assets. This project depends only on its contained `packages/diagnostics_core` path, Flutter and shared preferences; it can be copied and built independently of the Full repository.
