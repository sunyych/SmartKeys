# Installed applications in Desktop Launchpad

Full and Desktop 1.7.0 support choosing local installed applications for the
twelve Launchpad slots. In Desktop, edit a slot, search the installed application
list, or refresh it. **Add local application** registers a local executable,
Windows shortcut, macOS application bundle, Linux desktop entry, or executable
AppImage when it is absent from the OS inventory. A registration must be saved
successfully before it can be assigned. Cancelling the picker preserves the slot.

Windows discovery reads Start Apps (including packaged app IDs), user/common
Start Menu shortcuts, and App Paths registrations. macOS combines standard
application folders with Spotlight and resolves bundle identities through
LaunchServices. Linux uses GIO's visible application registry, respecting XDG
desktop entry handling. Portable applications and applications deliberately
hidden from an OS launcher can be added locally. Discovery does not launch apps.

The inventory is cached for at least sixty seconds. Refresh runs separately from
the existing three-second foreground checks. Discovery, target validation, and
process output have explicit limits. A failed refresh preserves saved slots;
unavailable applications retain their label and cannot be launched. Missing
historical inventory entries do not accumulate indefinitely.

Only the dynamic applications assigned to the twelve slots are synchronized to
the phone. Synced records contain opaque `installed.<hash>` IDs, display metadata,
and launch-only capability. Executable paths, shortcut arguments, and bundle or
desktop-entry locations stay on the computer. The phone cannot supply a path or
shell command, and the legacy launch endpoint also accepts registered IDs only.
The computer rechecks current registration, slot assignment, and the automatic
launch setting immediately before OS handoff. The icon resolver is separate, so
unassigned applications can still show native icons in the local picker.

Launch-only applications do not acquire managed shortcut layouts or claim a
confirmed foreground state. The existing managed applications retain their
foreground and shortcut protections. A successful OS handoff means the operating
system accepted the request; it does not prove that the application's window has
finished opening. These changes do not add Bluetooth Lite launching features.

Implementation: `installed_app_registry.dart` stores and validates local targets;
`installed_app_discovery.dart` enumerates OS entries; `installed_app_picker.dart`
provides the searchable virtual list; the controller projects the selected
launch-only records. Native activation and icons resolve the ID back to the
current Desktop-owned target. Manual persistence rejects more than 1,000 entries
or more than 2 MiB of UTF-8 JSON before writing, matching restart-time validation.
