# Lite Bluetooth Parity Implementation Plan

**Goal:** Match Full's landscape interface while executing configured local
shortcuts exclusively through Bluetooth HID.

**Architecture:** Standalone controller and local stores feed a Lite-owned surface
and settings editors. Existing native HID and pointer encoding remain the input
boundary. Launcher configuration supplies keyboard combinations only.

**Spec:** ../specs/2026-11-17-lite-bluetooth-parity-design.md

## Global constraints

Lite 1.2.0+3, package com.lumiaiq.bluetoothlite; Full/Desktop 1.7.0+9 unchanged.
No new production dependencies, network, microphone, KVM or native app launch.
Twelve launch slots; preserve old saved shortcut lists and data on upgrade.

## Tasks

- [ ] Core freezes concrete DTO/controller API with other coders, extracts input
  state from main.dart, adds launcher persistence and consumer-control shortcuts.
  Add regression tests for failed persistence, exact saved launch HID, all input
  guards and host/configuration changes. Keep main exports/constructor compatibility.
- [ ] Interface builds the matching rail/header/grid/touchpad surface and local
  Bluetooth connection navigation, registers the existing brand asset and version.
  Preserve gesture callbacks; add bounded layout and current screenshot tests.
- [ ] Platform builds local settings/editors using the frozen controller, validates
  keyboard-only launch bindings and media shortcut editing, and declares landscape
  on Android. Extend real source/APK isolation and native input acceptance checks.
- [ ] Root reviews integration and data migration, resolves cross-owner issues via
  Luna, runs standalone Flutter/native checks and captures current UI fixtures.
- [ ] Root builds a fresh NTFS independent export, checks packaged AOT/brand/icons/
  signature/version, upgrades only the existing Lite package, verifies navigation,
  commits/pushes the feature, merges main and delivers APK/source/verification notes.

Production changes are implemented by Luna coders. Only Root performs Git merges,
device installation and final delivery. Existing Full files are references, not
new runtime dependencies of Lite.
