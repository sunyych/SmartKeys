# WIP snapshot: mobile launcher, icon service, and editions

This snapshot is intentionally unfinished. It preserves the prior local implementation for review and selective reuse; it is not a merge-ready change or a validated release.

## Branch and comparison baseline

- WIP branch: `feature/mobile-launcher-and-editions`.
- Original implementation base: `0f67178`.
- Handoff already committed separately: `68c7872`.
- Latest fetched main when this snapshot was prepared: `791b022`.
- Main was fetched for comparison, not merged into this worktree.

## What main already implements

Main contains its own mobile-edition implementation in `ec68223`, followed by build-validation and device-installation records. It uses Android flavors and Dart entry points for Regular and Lite. Its Regular surface defaults to a Launchpad, uses left navigation, a twelve-cell shortcut surface and right touchpad, and receives installed applications from Desktop. See `docs/MOBILE_EDITIONS.md` and `docs/MOBILE_EDITIONS_VALIDATION.md` on main for its own claimed validation evidence.

## What this WIP preserves

- A different edition-isolation approach: an independent `apps/bluetooth` Android Flutter project, build/check/export scripts, and artifact-only CI workflows.
- Eight Desktop-configured launcher slots published through the companion manifest, mobile Launcher Pad, and responsive navigation changes.
- Native Desktop app-icon extraction, an authenticated companion icon resource endpoint, mobile icon caching and artwork components.
- A same-origin centralized icon catalog/download page in the Rust dashboard service, bundled PNG/SVG resources and source notes.
- Linux X11 automation/media/mute implementation work and a Linux build workflow.
- Associated protocol, widget, screenshot tests and documentation.

## Integration warning

Do not merge this snapshot blindly over main. The mobile-edition, home-screen, protocol and Desktop-controller approaches overlap and differ. Main’s newer implementation must be reviewed first; retain useful icon/download/Linux changes and deliberately resolve the product architecture rather than keeping duplicate competing entry points.

## Validation status and known unfinished work

- The complete current WIP has not passed unified regression or all platform builds.
- The prior targeted mobile run had failures because tests still assumed the old keyboard-first homepage/navigation. Some source was changed afterwards; rerun rather than assuming all old failures still reproduce.
- Protocol tests passed during development; icon-server/browser checks and a Desktop suite also passed at intermediate points. These are not final validation of this entire snapshot.
- Lite basic input/persistence tests passed at an intermediate point. Its screenshot font-loading hang and dialog controller lifecycle were repaired but require a clean final rerun.
- Lite Gradle emitted an APK under `apps/bluetooth/android/build/`, while Flutter could not locate the expected output. Fix its build-directory configuration and rerun the official Flutter build command.
- Validate actual independence of exported Lite source, permissions/dependencies, release signing configuration and CI portability.
- Finish icon coverage/download integration and verify cross-computer cache isolation and icon-sync settings.
- Linux X11 support and Linux CI dependencies require review; do not claim Wayland automation or unexecuted native-platform checks as passing.

The earlier complete handoff remains in `docs/handoffs/2026-11-17-mobile-launcher-and-editions.md`. Its feature requirements and detailed code map remain useful; the main-branch comparison in this snapshot supersedes its older remote-state description.

Build outputs, APKs, Gradle/Flutter caches, generated plugin registration, local SDK settings and signing material are intentionally excluded from this commit. No source files were deleted to clean those artifacts.
