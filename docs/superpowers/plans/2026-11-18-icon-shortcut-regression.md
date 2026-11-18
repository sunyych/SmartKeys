# Icon and shortcut regression completion

**Goal:** Complete meaningful automated coverage for App artwork, OS shortcut libraries, phone sidebar and host-switch input before merging to main.

**Architecture:** Reuse the actual catalog, decoders, controllers and HTTP endpoints. Test observable state and dispatched input, including persistence failures and stale sessions. Keep physical OS permissions and third-party shortcut behavior separate from automated acceptance.

## Work and acceptance

- [x] Delegate Full/catalog, Desktop/protocol, Lite/server/browser audits to Luna agents; identify missing behavior before adding tests.
- [ ] Full: cover catalog-to-profile icon/OS identity, configured/unassigned input, host switching and existing controller/widget regressions.
- [ ] Desktop/protocol: cover macOS/Linux installation, bundle artwork plus profile atomic persistence, customization/reload and synchronized sidebar metadata.
- [ ] Lite/browser: cover delayed and concurrent persistence, private launch-key preservation and damaged download rejection; retain server HTTP and legacy-icon regressions.
- [ ] Run all Flutter suites with LCOV, shared-package suites, Python generators/export/APK guards, Rust and real browser tests. Analyze application projects and check generated mirrors.
- [ ] Keep Full, Desktop and Lite coverage artifacts in CI; verify Windows/Android, Apple and Linux builds on the reviewed commit. Investigate failures rather than hiding failing tests.
- [ ] Review diffs and evidence, commit/push the feature branch, merge to main without overwriting concurrent work, and push main. Record remaining physical-device acceptance boundaries honestly.

## Reproduction

Use Flutter 3.44.2. From each of the root, `desktop_companion`, and `apps/bluetooth` projects, run `flutter analyze` then `flutter test --coverage`. Run `flutter test --dart-define=LUMIAKEY_POINTER_DIAGNOSTICS=true test/pointer_diagnostics_test.dart` in the root separately. Run `dart test` in shared Dart packages, the Python unit modules under `scripts`, and the community-server workflow for PostgreSQL/Docker/browser integration. LCOV reports describe instrumented source lines, not physical shortcut correctness or complete branch coverage.
