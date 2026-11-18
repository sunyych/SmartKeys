# macOS pointer control troubleshooting

LumiaKey Advanced mode sends touchpad move, click, and scroll batches over the authenticated local `/pointer` endpoint. The Mac companion checks Accessibility and event-posting permission before it creates and posts native CoreGraphics mouse events.

## Permission and installation identity

The native Mac companion returns `pointer_permission_missing` when either permission check fails. It still advertises the mouse-control capability, so a connected phone can show the touchpad; the phone now displays a permission/connection error beside it after a rejected batch. On the Mac, open **LumiaKey Desktop → General → Allow Mac mouse and keyboard control**. Use **Request**, **Settings**, or **Refresh** as needed. These controls reuse the existing dictation permission flow and never grant permission automatically.

macOS ties Accessibility permission to the app's signing identity. Ad-hoc builds can change their designated code requirement when rebuilt, leaving a stale Settings entry. If LumiaKey Desktop is already enabled but input is still rejected, remove the old entry and add the currently installed `/Applications/LumiaKey.app` again. Install a stable Apple Development-signed build before granting permission; the user must enable the current app themselves.

## Pointer movement

Mac movement events use an absolute CoreGraphics event location. Each relative movement updates the in-memory cursor position so later events in the same batch use the updated point. Targets are clamped to the nearest active display rectangle, including monitors positioned left or above the primary display. Tests construct real CGEvents and inspect their location but do not post them.

## Evidence and limits

On the affected Mac, a live authenticated zero-movement request to the installed companion's `/pointer` endpoint returned HTTP 400 with `pointer_permission_missing`, even though older LumiaKey entries appeared enabled. That confirms an event-permission failure for that installed build; it does not prove the permission state of a newly stable-signed installation. Separately, source inspection and the CGEvent regression test confirm that the previous movement event kept the old absolute location while only setting delta fields. Click and scroll depend on the same native posting permission, so the permission rejection accounts for all three actions on the affected installation.

The installed `/Applications/LumiaKey.app` is now signed with the existing Apple Development certificate, and deep code-signature validation passed. A zero-movement request from that new process still returned HTTP 400 `pointer_permission_missing`; the user is being asked to remove the stale Accessibility entry and add the current app. Physical phone-to-Mac input acceptance is not yet confirmed. No permission is granted by the app or this change.
