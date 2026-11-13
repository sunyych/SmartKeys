import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/models/computer_setup.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/shortcut_grid_geometry.dart';
import 'package:smart_keys/ui/standalone_app_panel.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    final orientation = size.width < size.height ? 'portrait' : 'landscape';

    testWidgets('Bluetooth shortcut tiles match in $orientation', (
      tester,
    ) async {
      _setViewport(tester, size);
      final harness = await TestHarness.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });

      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pumpAndSettle();
      _expectUniformSizes(
        tester,
        [
          for (var index = 0; index < 15; index++)
            ValueKey('control-button-$index'),
        ],
        _expectedCellSize(size),
        grid: find.byKey(
          ValueKey('button-grid-${orientation == 'portrait' ? '3x5' : '5x3'}'),
        ),
      );
    });

    testWidgets('standalone app shortcuts match in $orientation', (
      tester,
    ) async {
      _setViewport(tester, size);
      final harness = await TestHarness.create();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });
      final target = harness.controller.activeComputer!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: StandaloneAppPanel(
                controller: harness.controller,
                target: target,
                application: computerApplicationById('claude')!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final keys = [
        'voiceMode',
        'toggleVoiceMode',
        'voiceInput',
        'cancelClear',
      ].map((id) => ValueKey('standalone-action-claude-$id')).toList();
      for (final key in keys) {
        await tester.ensureVisible(find.byKey(key));
      }
      _expectUniformSizes(tester, keys, _expectedCellSize(size));
    });

    testWidgets('Desktop app shortcut tiles match in $orientation', (
      tester,
    ) async {
      _setViewport(tester, size);
      final harness = await TestHarness.create(seedComputerSetup: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });
      final starter = DesktopManifest.starter();
      harness.companion.host.value = connectedCompanionHost;
      harness.companion.syncedManifest.value = starter.copyWith(
        computerId: 'desktop-grid-size-test',
        applications: [
          for (final app in starter.applications)
            if (app.id == 'chatgpt')
              app.copyWith(detected: true, running: true, foreground: true),
        ],
      );
      harness.companion.status.value = CompanionSyncStatus.ready;
      await harness.controller.saveComputerSetup(
        harness.controller.activeComputer!,
        ComputerSetup(applicationIds: const ['chatgpt']),
      );

      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-app-chatgpt')));
      await tester.pumpAndSettle();
      final grid = find.byKey(const ValueKey('remote-layout-chatgpt'));
      final projected = projectChatGptLayout(
        starter.layoutById('chatgpt')!,
        RemoteShortcutPlatform.apple,
      );
      _expectUniformSizes(
        tester,
        [
          for (final button in projected.buttons.take(15))
            ValueKey('remote-button-${button.id}'),
        ],
        _expectedCellSize(size),
        grid: grid,
      );
    });

    testWidgets('KVM-selected Desktop tiles match in $orientation', (
      tester,
    ) async {
      _setViewport(tester, size);
      final companion = _KvmCompanion()
        ..choices.value = const [
          CompanionComputerChoice(
            id: 'desktop-kvm-size',
            name: 'Studio PC',
            platform: 'windows',
          ),
        ];
      final harness = await TestHarness.create(
        seedComputerSetup: false,
        platformOverride: TargetPlatform.android,
        companionService: companion,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await harness.dispose();
      });
      companion.connectInitial('desktop-kvm-size');
      await harness.controller.switchComputer('desktop:desktop-kvm-size');
      final starter = DesktopManifest.starter();
      companion.syncedManifest.value = starter.copyWith(
        computerId: 'desktop-kvm-size',
        applications: [
          for (final app in starter.applications)
            if (app.id == 'chrome')
              app.copyWith(detected: true, running: true, foreground: true),
        ],
      );
      companion.status.value = CompanionSyncStatus.ready;
      await harness.controller.saveComputerSetup(
        harness.controller.activeComputer!,
        ComputerSetup(applicationIds: const ['chrome']),
      );

      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pumpAndSettle();
      expect(harness.controller.hasPinnedDesktopComputer, isTrue);
      await tester.tap(find.byKey(const ValueKey('workspace-app-chrome')));
      await tester.pumpAndSettle();
      _expectUniformSizes(
        tester,
        [
          for (final button
              in starter.layoutById('app.chrome')!.buttons.take(15))
            ValueKey('remote-button-${button.id}'),
        ],
        _expectedCellSize(size),
        grid: find.byKey(const ValueKey('remote-layout-app.chrome')),
      );
    });

    if (orientation == 'portrait') {
      testWidgets('Vibe Cursor portrait tiles match the shared cell size', (
        tester,
      ) async {
        _setViewport(tester, size);
        final harness = await TestHarness.create(seedComputerSetup: false);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness.dispose();
        });
        harness.companion.host.value = connectedCompanionHost;
        harness.companion.syncedManifest.value = desktopManifest(
          installed: const {'cursor'},
          running: const {'cursor'},
          foreground: 'cursor',
        );
        harness.companion.status.value = CompanionSyncStatus.ready;
        await harness.controller.saveComputerSetup(
          harness.controller.activeComputer!,
          ComputerSetup(applicationIds: const ['cursor']),
        );

        await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('workspace-app-cursor')));
        await tester.pumpAndSettle();
        _expectUniformSizes(
          tester,
          [
            const ValueKey('vibe-button-vibe.cursor.project'),
            const ValueKey('vibe-button-vibe.cursor.newChat'),
            const ValueKey('vibe-button-vibe.cursor.cancel'),
          ],
          _expectedCellSize(size),
          grid: find.byKey(const ValueKey('vibe-shortcut-grid')),
        );
      });
    }
  }
}

Size _expectedCellSize(Size viewport) {
  final geometry = ShortcutGridGeometry.forViewport(
    viewport: viewport,
    gridContentWidth: ShortcutGridGeometry.contentWidthForViewport(
      viewport,
      safeAreaLeft: viewport.width > viewport.height ? 24 : 0,
      safeAreaRight: viewport.width > viewport.height ? 24 : 0,
    ),
    keysPerPage: 15,
    safeAreaVertical: 0,
  );
  return Size(geometry.width, geometry.height);
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.viewPadding = FakeViewPadding(
    left: size.width > size.height ? 24 : 0,
    right: size.width > size.height ? 24 : 0,
  );
  tester.view.padding = FakeViewPadding(
    left: size.width > size.height ? 24 : 0,
    right: size.width > size.height ? 24 : 0,
  );
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetPadding);
}

void _expectUniformSizes(
  WidgetTester tester,
  List<ValueKey<String>> keys,
  Size expected, {
  Finder? grid,
}) {
  final sizes = keys.map((key) => tester.getSize(find.byKey(key))).toList();
  for (final size in sizes) {
    expect(size.width, closeTo(expected.width, 0.01));
    expect(size.height, closeTo(expected.height, 0.01));
  }
  for (final size in sizes.skip(1)) {
    expect(size.width, closeTo(sizes.first.width, 0.01));
    expect(size.height, closeTo(sizes.first.height, 0.01));
  }
  if (grid != null) {
    final visible = tester.getRect(grid).inflate(0.01);
    for (final key in keys) {
      final tile = tester.getRect(find.byKey(key));
      expect(visible.contains(tile.topLeft), isTrue, reason: '$key top edge');
      expect(
        visible.contains(tile.bottomRight),
        isTrue,
        reason: '$key bottom edge',
      );
    }
  }
}

class _KvmCompanion extends RecordingCompanionService
    implements SwitchableCompanionConnection {
  final ValueNotifier<List<CompanionComputerChoice>> choices = ValueNotifier(
    const [],
  );
  String? selectedId;
  bool selectionPinned = false;

  @override
  ValueListenable<List<CompanionComputerChoice>> get computerChoices => choices;

  @override
  String? get selectedComputerChoiceId => selectedId;

  @override
  bool get isComputerSelectionPinned => selectionPinned;

  @override
  Future<void> selectComputer(String id) async => connectInitial(id);

  @override
  Future<void> suspendComputerSelection() async {
    selectionPinned = false;
    selectedId = null;
    host.value = null;
    status.value = CompanionSyncStatus.disconnected;
    syncedManifest.value = null;
  }

  void connectInitial(String id) {
    selectedId = id;
    selectionPinned = true;
    final choice = choices.value.singleWhere((choice) => choice.id == id);
    host.value = CompanionHost(
      name: choice.name,
      platform: choice.platform,
      address: '127.0.0.1',
      port: 45678,
      token: 'kvm-test-token',
      computerId: id,
      protocolVersion: 2,
      capabilities: const {'manifest'},
    );
    syncedManifest.value = DesktopManifest.starter().copyWith(computerId: id);
    status.value = CompanionSyncStatus.ready;
  }

  @override
  void dispose() {
    choices.dispose();
    super.dispose();
  }
}
