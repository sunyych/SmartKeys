# Installed-application Launchpad and header validation

Full mobile and Desktop are **1.7.0+9**. Independent Android Bluetooth Lite
remains **1.1.0+2** and is unchanged by this increment. Implementation commit:
`6cb5f6de731f70efb12fa9b6029c2d435a712842`. Subsequent fixture fixes change
tests only, preserving the runtime sources used to build the packages.

## Delivered behavior

- The shared mobile header places the host, clock, play/pause and mute controls
  centrally, beside the workspace title. The right touchpad and twelve landscape
  keys remain. The microphone overlay reserves space beside Settings.
- The rail uses the existing LumiaKey brand asset and places the wordmark below
  it at the top, removing the former bottom wordmark.
- Desktop searches OS-discovered applications and supports selecting a local
  executable, shortcut, application bundle or desktop entry for portable and
  unindexed applications. Manual registrations persist across restart.
- Additional applications are launch-only. Only selected dynamic records reach
  the phone; locators, arguments and native icon file paths remain local.
  Managed shortcut and foreground behavior retains its existing checks.

See [installed application usage and boundaries](../INSTALLED_APPLICATIONS.md)
and the [design](../superpowers/specs/2026-11-17-installed-launchpad-and-header-design.md).

## Local verification

| Check | Result |
| --- | --- |
| Full suite with synchronized UDP fixtures | 333 passed |
| Desktop final serial suite | 133 passed; one Linux-only test skipped on Windows |
| Shared protocol | 30 passed |
| Android native unit tests | 16 passed |
| Native API/controller focused suite | 19 passed |
| Registry, discovery and picker focused suite | 26 passed |
| Final Companion synchronization fixture suite | 14 passed |
| Concurrent network regression group | 27 passed |
| Full / Desktop / protocol analysis | Clean |
| Generated icon catalog / diagnostics vendor checks | Clean |

The read-only Windows inventory found **672 launch entries in 8.6 seconds**:
355 AppIDs, 219 Start Menu shortcuts and 98 App Paths registrations. Entries can
represent multiple launch registrations for the same application. No application
was launched by discovery. The native Chrome icon extraction test passes with
the original three-second production budget. The complete Desktop suite also
passes with that budget when run serially.

The CI-only picker failure was caused by a fixture accessing synthetic Linux
paths through real filesystem I/O. Its native icon service is now explicitly
injected and teardown is unconditional. The connection fixture atomically binds
its UDP port and gates both possible manifest/action response orders. Its
original revision, ready-state, request-count and error assertions remain.
The remaining UDP fixtures also bind atomically and register state listeners
before advertising. Expiry tests advance a controlled clock; competing-host
tests await actual receipt and retain the active-host/token and rejected-server
request assertions. Disposal is cleaned up even if an earlier phase fails.
These fixture fixes do not change product timeouts or weaken the assertions.

## Builds and hosted validation

Windows Release and optimized Android Release were built locally. Their inputs
and packaged icon hashes were checked. Android reports package
`com.lumiaiq.smartkey`, version `1.7.0`, code `9`, with the existing development
certificate for an in-place update. The Windows portable package matches 102
current build-input files. All fifty packaged built-in icons match the catalog.

- [Apple iOS and macOS builds](https://github.com/sunyych/SmartKeys/actions/runs/44237960757)
- [Linux tests and native release build](https://github.com/sunyych/SmartKeys/actions/runs/44238569722)
- [Full Android and Windows validation](https://github.com/sunyych/SmartKeys/actions/runs/44239030897)

The final delivery manifest records the checked run conclusions, source and main
commits, package sizes and SHA-256 hashes. Forty-four current widget-rendered
captures include ten Full screens and thirty-four Desktop screens; these use
fixtures and do not establish physical input delivery.

## Installation and scope

The current Windows computer was upgraded to Desktop **1.7.0+9**, with both
existing configuration directories backed up. The installed authenticated
service reports twelve slots and `installed-launcher-v1`; unauthenticated info
is rejected. A real native Chrome PNG and its ETag response were verified.

The connected Android phone was upgraded with `adb install -r` to Full
**1.7.0/code9**, preserving its data. Lite **1.1.0/code2** remains installed.
No permission grants, uninstall, reset, shortcut input or diagnostic sharing
were performed. Physical Full navigation was stopped at the secure keyguard;
the actual Settings-to-icon-library route is covered by widget regression tests.

Windows packages remain unsigned; Android uses the existing development signing
certificate; macOS is not notarized. The iOS artifact is an unsigned app ZIP and
requires Apple signing/provisioning. Apple/Linux physical devices, actual
launching of personal applications, HID delivery and ASR accuracy were not
exercised. Online center endpoints remain unconfigured.
