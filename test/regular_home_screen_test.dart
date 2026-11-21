import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/codex_activity.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/ui/dictation_entry_consent.dart';
import 'package:smart_keys/ui/local_dictation_panel.dart';
import 'package:smart_keys/app.dart';
import 'package:smart_keys/ui/regular_home_screen.dart';

import 'regular_home_test_support.dart';
import 'test_support.dart';

Future<TestHarness> mountRegular(
  WidgetTester tester, {
  RecordingCompanionService? companion,
  DesktopManifest? manifest,
  CompanionHost? host,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(844, 390);
  final harness = await TestHarness.create(
    companionService: companion ?? ActivatingRegularCompanion(),
  );
  connectRegularHarness(harness, manifest: manifest);
  if (host != null) harness.companion.host.value = host;
  await tester.pumpWidget(regularTestApp(harness));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    await harness.dispose();
  });
  return harness;
}

class DeferredRegularCompanion extends RecordingCompanionService {
  final launch = Completer<void>();
  @override
  Future<void> executeRemote(RemoteActionRequest request) async {
    remoteActions.add(request);
    if (request.kind == RemoteActionKind.launchApplication) await launch.future;
  }
}

void main() {
  testWidgets('one right header computer control opens the shared switcher', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    final switcher = find.byKey(const ValueKey('computer-kvm-switch'));
    final removedDuplicate = find.byKey(
      const ValueKey('regular-desktop-connection'),
    );

    expect(switcher, findsOneWidget);
    expect(removedDuplicate, findsNothing);
    expect(tester.getRect(switcher).right, lessThanOrEqualTo(844));
    await tester.tap(switcher);
    await tester.pumpAndSettle();
    expect(find.text('Switch computer'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    harness.companion.host.value = null;
    harness.companion.syncedManifest.value = null;
    harness.companion.status.value = CompanionSyncStatus.disconnected;
    await tester.pumpAndSettle();

    expect(switcher, findsOneWidget);
    expect(removedDuplicate, findsNothing);
    expect(
      find.byKey(const ValueKey('regular-connect-desktop')),
      findsOneWidget,
    );
    expect(tester.getRect(switcher).right, lessThanOrEqualTo(844));
    await tester.tap(switcher);
    await tester.pumpAndSettle();
    expect(find.text('Switch computer'), findsOneWidget);
    expect(find.text('No paired computers yet'), findsOneWidget);
  });

  testWidgets('only the ChatGPT App Bar item shows real Codex activity', (
    tester,
  ) async {
    final service = ActivatingRegularCompanion();
    await mountRegular(tester, companion: service);
    final chatGpt = find.byKey(const ValueKey('regular-nav-chatgpt'));
    final dot = find.byKey(const ValueKey('regular-chatgpt-activity-dot'));
    expect(dot, findsNothing);
    final colors = <Color>{};
    for (final (status, label) in [
      (CodexActivityStatus.idle, 'Idle'),
      (CodexActivityStatus.thinking, 'Thinking'),
      (CodexActivityStatus.complete, 'Complete'),
      (CodexActivityStatus.needsInput, 'Needs Input'),
      (CodexActivityStatus.error, 'Error'),
    ]) {
      service.codexActivity.value = status;
      await tester.pump();
      expect(dot, findsOneWidget);
      expect(find.descendant(of: chatGpt, matching: dot), findsOneWidget);
      expect(find.byTooltip('Codex activity: $label'), findsOneWidget);
      final decoration =
          tester.widget<DecoratedBox>(dot).decoration as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
      expect(
        decoration.border,
        status == CodexActivityStatus.idle ? isNotNull : isNull,
      );
      expect(
        tester.getCenter(dot).dx,
        greaterThan(tester.getCenter(chatGpt).dx),
      );
      colors.add(decoration.color!);
    }
    expect(colors, hasLength(5));
    service.codexActivity.value = null;
    await tester.pump();
    expect(dot, findsNothing);
  });

  testWidgets('ChatGPT opens the combined Micro layout and retains Review', (
    tester,
  ) async {
    await mountRegular(tester);
    await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('regular-nav-codex')), findsNothing);
    final dictation = find.byKey(
      const ValueKey('regular-button-$chatGptLocalDictationShortcutId'),
    );
    final voice = find.byKey(
      const ValueKey('regular-button-$chatGptNativeVoiceShortcutId'),
    );
    final mode = find.byKey(const ValueKey('regular-button-chatgpt.codexMode'));
    expect(mode, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('regular-cell-11')),
        matching: dictation,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('regular-cell-8')),
        matching: voice,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dictation, matching: find.text('Dictation')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: voice, matching: find.text('Voice Mode')),
      findsOneWidget,
    );
    for (final id in [
      'chatgpt.codex.send',
      'chatgpt.codex.copy',
      'chatgpt.codex.paste',
      chatGptFastModeShortcutId,
      chatGptBranchOffShortcutId,
      chatGptApproveShortcutId,
      chatGptDeclineShortcutId,
      chatGptNativeVoiceShortcutId,
    ]) {
      expect(find.byKey(ValueKey('regular-button-$id')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('regular-next-page')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('regular-cell-0')),
        matching: find.byKey(
          const ValueKey('regular-button-chatgpt.codex.review'),
        ),
      ),
      findsOneWidget,
    );
    expect(mode, findsOneWidget);
  });

  testWidgets('unassigned Micro keys explain how to bind without sending', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
    await tester.pumpAndSettle();
    for (final id in [chatGptFastModeShortcutId, chatGptBranchOffShortcutId]) {
      await tester.tap(find.byKey(ValueKey('regular-button-$id')));
      await tester.pumpAndSettle();
    }
    expect(
      find.textContaining('Assign and enable this shortcut'),
      findsOneWidget,
    );
    expect(harness.companion.remoteActions.single.applicationId, 'chatgpt');
  });

  testWidgets('Windows Voice without a binding opens native setup only', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final harness = await mountRegular(tester);
    await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('regular-button-$chatGptNativeVoiceShortcutId'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Set up Voice Mode'), findsOneWidget);
    expect(find.textContaining('ChatGPT → Settings → Voice'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('dictation-entry-explanation')),
      findsNothing,
    );
    expect(harness.companion.remoteActions.single.applicationId, 'chatgpt');
  });

  testWidgets('configured Windows Voice sends only the native action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      dictationConsentPreferenceKey: true,
    });
    final base = DesktopManifest.regularStarter();
    final harness = await mountRegular(
      tester,
      manifest: base.copyWith(
        layouts: [
          for (final layout in base.layouts)
            if (layout.id != 'chatgpt')
              layout
            else
              layout.copyWith(
                buttons: [
                  for (final button in layout.buttons)
                    if (button.id == chatGptNativeVoiceShortcutId)
                      saveExplicitChatGptVoiceBinding(
                        button.copyWith(shortcut: const ['CTRL', 'SHIFT', 'V']),
                        RemoteShortcutPlatform.windows,
                      )
                    else
                      button,
                ],
              ),
        ],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey('regular-button-$chatGptNativeVoiceShortcutId'),
      ),
    );
    await tester.pumpAndSettle();
    expect(harness.companion.remoteActions.map((action) => action.buttonId), [
      null,
      chatGptNativeVoiceShortcutId,
    ]);
    expect(find.text('Set up Voice Mode'), findsNothing);
    expect(
      find.byKey(const ValueKey('dictation-entry-explanation')),
      findsNothing,
    );
  });

  testWidgets(
    'legacy synced ChatGPT adds Dictation in cell 12 and keeps Voice separate',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final base = DesktopManifest.regularStarter();
      const legacyNativeVoice = RemoteShortcutButton(
        id: chatGptNativeVoiceShortcutId,
        name: 'Start Voice Chat',
        icon: '',
        targetType: RemoteTargetType.keyboardShortcut,
        description: 'CTRL + SHIFT + V',
        enabled: false,
      );
      final harness = await mountRegular(
        tester,
        manifest: base.copyWith(
          layouts: [
            for (final layout in base.layouts)
              if (layout.id != 'chatgpt')
                layout
              else
                layout.copyWith(
                  buttons: [
                    for (final button in layout.buttons)
                      if (button.id == chatGptNativeVoiceShortcutId)
                        legacyNativeVoice
                      else if (!{
                        chatGptLocalDictationShortcutId,
                        chatGptFastModeShortcutId,
                        chatGptBranchOffShortcutId,
                      }.contains(button.id))
                        button,
                  ],
                ),
          ],
        ),
      );
      harness.companion.host.value = CompanionHost(
        name: regularTestHost.name,
        computerId: regularTestHost.computerId,
        platform: regularTestHost.platform,
        address: regularTestHost.address,
        port: regularTestHost.port,
        token: regularTestHost.token,
        protocolVersion: regularTestHost.protocolVersion,
        capabilities: {
          ...regularTestHost.capabilities,
          'chatgpt-platform-layout-v1',
        },
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
      await tester.pumpAndSettle();
      final dictation = find.descendant(
        of: find.byKey(const ValueKey('regular-cell-11')),
        matching: find.byKey(
          const ValueKey('regular-button-$chatGptLocalDictationShortcutId'),
        ),
      );
      expect(dictation, findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('regular-cell-8')),
          matching: find.text('Voice Mode'),
        ),
        findsOneWidget,
      );
      for (final (cell, label) in [
        (4, 'Fast Mode'),
        (5, 'Approve'),
        (6, 'Decline'),
        (7, 'Branch Off'),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('regular-cell-$cell')),
            matching: find.text(label),
          ),
          findsOneWidget,
        );
        final control = tester.widget<InkWell>(
          find.descendant(
            of: find.byKey(ValueKey('regular-cell-$cell')),
            matching: find.byType(InkWell),
          ),
        );
        expect(control.onTap, isNotNull);
      }
      await tester.tap(dictation);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictation-entry-explanation')),
        findsOneWidget,
      );
      expect(find.text('Set up Voice Mode'), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('dictation-explanation-cancel')),
      );
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions.single.applicationId, 'chatgpt');
    },
  );

  testWidgets('Mac Dictate runs the advertised system action in cell 12', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final base = DesktopManifest.regularStarter();
    final chatGpt = base.layoutById('chatgpt')!;
    final modernLayout = chatGpt.copyWith(
      buttons: [
        for (final button in chatGpt.buttons)
          if (button.id == chatGptLocalDictationShortcutId)
            const RemoteShortcutButton(
              id: chatGptSystemDictationShortcutId,
              name: 'Dictate',
              icon: 'mic_external_on',
              targetType: RemoteTargetType.system,
              target: chatGptSystemDictationTarget,
              description: 'Start macOS Dictation using your system settings.',
            )
          else
            button,
      ],
    );
    final manifest = base.copyWith(
      layouts: [
        for (final layout in base.layouts)
          if (layout.id == 'chatgpt') modernLayout else layout,
      ],
    );
    final macHost = CompanionHost(
      name: 'Studio Mac',
      computerId: 'regular-test-mac',
      platform: 'macos',
      address: regularTestHost.address,
      port: regularTestHost.port,
      token: 'regular-test-mac',
      protocolVersion: 2,
      capabilities: {
        ...regularTestHost.capabilities,
        'chatgpt-platform-layout-v1',
        chatGptSystemDictationCapability,
      },
    );
    final harness = await mountRegular(
      tester,
      manifest: manifest,
      host: macHost,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
    await tester.pumpAndSettle();

    final dictateKey = ValueKey(
      'regular-button-$chatGptSystemDictationShortcutId',
    );
    final dictate = find.descendant(
      of: find.byKey(const ValueKey('regular-cell-11')),
      matching: find.byKey(dictateKey),
    );
    expect(dictate, findsOneWidget);
    expect(find.byKey(dictateKey), findsOneWidget);
    expect(
      find.descendant(of: dictate, matching: find.text('Dictate')),
      findsOneWidget,
    );
    await tester.tap(dictate);
    await tester.pumpAndSettle();
    expect(
      harness.companion.remoteActions.last.buttonId,
      chatGptSystemDictationShortcutId,
    );
  });

  testWidgets('Mac without Dictate capability shows an update action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final oldMacHost = CompanionHost(
      name: 'Older Studio Mac',
      computerId: 'regular-test-old-mac',
      platform: 'macos',
      address: regularTestHost.address,
      port: regularTestHost.port,
      token: 'regular-test-old-mac',
      protocolVersion: 2,
      capabilities: {
        ...regularTestHost.capabilities,
        'chatgpt-platform-layout-v1',
      },
    );
    final harness = await mountRegular(tester, host: oldMacHost);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
    await tester.pumpAndSettle();

    final dictate = find.descendant(
      of: find.byKey(const ValueKey('regular-cell-11')),
      matching: find.byKey(
        const ValueKey('regular-button-$chatGptSystemDictationShortcutId'),
      ),
    );
    expect(dictate, findsOneWidget);
    expect(
      find.descendant(of: dictate, matching: find.text('Dictate')),
      findsOneWidget,
    );
    await tester.tap(dictate);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Update LumiaKey Desktop to use macOS Dictation from your phone.',
      ),
      findsOneWidget,
    );
    expect(
      harness.companion.remoteActions.map((action) => action.buttonId),
      isNot(contains(chatGptSystemDictationShortcutId)),
    );
  });

  testWidgets(
    'approval keys require explicit confirmation and Send stays direct',
    (tester) async {
      final harness = await mountRegular(tester);
      await tester.tap(find.byKey(const ValueKey('regular-nav-chatgpt')));
      await tester.pumpAndSettle();
      final actions = harness.companion.remoteActions;
      for (final (id, confirmLabel) in [
        (chatGptApproveShortcutId, 'Approve Request'),
        (chatGptDeclineShortcutId, 'Decline Request'),
      ]) {
        final key = find.byKey(ValueKey('regular-button-$id'));
        final before = actions.length;
        await tester.tap(key);
        await tester.pumpAndSettle();
        expect(
          find.text('Does ChatGPT show an approval request?'),
          findsOneWidget,
        );
        expect(actions, hasLength(before));
        await tester.tap(find.text('Go Back'));
        await tester.pumpAndSettle();
        expect(actions, hasLength(before));
        await tester.tap(key);
        await tester.pumpAndSettle();
        await tester.tap(find.text(confirmLabel));
        await tester.pumpAndSettle();
        expect(actions, hasLength(before + 1));
        expect(actions.last.buttonId, confirmedChatGptApprovalShortcutId(id));
      }
      await tester.tap(
        find.byKey(const ValueKey('regular-button-chatgpt.codex.send')),
      );
      await tester.pumpAndSettle();
      expect(actions.last.buttonId, 'chatgpt.codex.send');
    },
  );

  testWidgets(
    'installed launch-only apps start promptly and keep Launchpad without empty shortcut profiles',
    (tester) async {
      final service = RecordingCompanionService();
      final harness = await mountRegular(tester, companion: service);
      const app = RemoteApplication(
        id: 'installed.0123456789abcdef0123456789abcdef',
        name: 'Word',
        icon: 'word',
        executable: 'Desktop-managed',
        layoutId: installedLaunchOnlyLayoutId,
        detected: true,
        launchOnly: true,
      );
      final base = service.syncedManifest.value!;
      service.syncedManifest.value = base.copyWith(
        layouts: [...base.layouts, installedLaunchOnlyLayout],
        applications: [...base.applications, app],
        launcherApplicationIds: [app.id, ...List<String?>.filled(11, null)],
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('regular-nav-${app.id}')), findsNothing);
      await tester.tap(find.byKey(ValueKey('regular-launch-${app.id}')));
      await tester.pumpAndSettle();
      expect(service.remoteActions.single.applicationId, app.id);
      expect(service.syncedManifest.value!.applicationActivationSequence, 0);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
            .data,
        'Launchpad',
      );
      expect(
        tester
            .widget<InkWell>(find.byKey(ValueKey('regular-launch-${app.id}')))
            .onTap,
        isNotNull,
      );
      expect(find.text('No shortcuts configured'), findsNothing);
      expect(
        find.textContaining('Could not open this application'),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('regular-nav-general')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('regular-button-keyboard.copy')),
      );
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions.last.buttonId, 'keyboard.copy');
    },
  );
  testWidgets(
    'shared top header keeps branding media tools and twelve-key touchpad geometry',
    (tester) async {
      await mountRegular(tester);
      for (final size in const [Size(844, 390), Size(1180, 820)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final header = tester.getRect(
          find.byKey(const ValueKey('regular-header')),
        );
        final title = tester.getRect(
          find.byKey(const ValueKey('regular-workspace-title')),
        );
        final controls = tester.getRect(
          find.byKey(const ValueKey('regular-header-controls')),
        );
        final tools = tester.getRect(
          find.byKey(const ValueKey('regular-header-tools')),
        );
        final grid = tester.getRect(
          find.byKey(const ValueKey('regular-twelve-key-grid')),
        );
        final pad = tester.getRect(
          find.byKey(const ValueKey('regular-touchpad')),
        );
        expect(controls.left, greaterThanOrEqualTo(title.right));
        expect(controls.right, lessThanOrEqualTo(tools.left));
        expect(
          (controls.center.dx - (size.width + 86) / 2).abs(),
          lessThan(20),
        );
        expect(header.bottom, lessThanOrEqualTo(grid.top));
        expect(header.bottom, lessThanOrEqualTo(pad.top));
        expect(grid.width / pad.width, closeTo(2, 0.12));
        for (final key in [
          'regular-host-name',
          'regular-clock',
          'regular-system-keyboard.playPause',
          'regular-system-keyboard.mute',
        ]) {
          expect(
            header.contains(tester.getCenter(find.byKey(ValueKey(key)))),
            true,
          );
        }
        final mic = tester.getRect(
          find.byKey(const ValueKey('local-quick-output')),
        );
        final settings = tester.getRect(
          find.byKey(const ValueKey('regular-settings')),
        );
        expect(mic.overlaps(settings), false);
        expect(header.contains(mic.center), true);
        final brand = tester.widget<Image>(
          find.byKey(const ValueKey('regular-brand-icon')),
        );
        expect(brand.semanticLabel, 'LumiaKey app icon');
        expect(
          (brand.image as ResizeImage).imageProvider,
          isA<AssetImage>().having(
            (value) => value.assetName,
            'brand source',
            'assets/app_icon/app_icon_source.png',
          ),
        );
        expect(find.text('LumiaKey'), findsOneWidget);
        expect(
          tester.getRect(find.byKey(const ValueKey('regular-brand-label'))).top,
          greaterThanOrEqualTo(
            tester
                .getRect(find.byKey(const ValueKey('regular-brand-icon')))
                .bottom,
          ),
        );
        expect(
          tester
              .getRect(find.byKey(const ValueKey('regular-brand-label')))
              .bottom,
          lessThan(
            tester
                .getRect(find.byKey(const ValueKey('regular-nav-launchpad')))
                .top,
          ),
        );
        expect(find.byKey(const ValueKey('regular-cell-11')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    },
  );
  testWidgets(
    'long host name and larger text fit shared header without losing tools',
    (tester) async {
      final harness = await mountRegular(tester);
      harness.companion.host.value = CompanionHost(
        name:
            'A very long Desktop workstation name that must stay in its own header space',
        computerId: regularTestHost.computerId,
        address: regularTestHost.address,
        port: regularTestHost.port,
        token: regularTestHost.token,
        platform: regularTestHost.platform,
        protocolVersion: regularTestHost.protocolVersion,
        capabilities: regularTestHost.capabilities,
      );
      await tester.pumpWidget(
        regularTestApp(
          harness,
          child: MediaQuery(
            data: MediaQueryData(
              size: const Size(844, 390),
              textScaler: TextScaler.linear(1.35),
            ),
            child: const RegularHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final host = tester.widget<Text>(
        find.byKey(const ValueKey('regular-host-name')),
      );
      expect(host.maxLines, 1);
      expect(host.overflow, TextOverflow.ellipsis);
      expect(
        find.byKey(const ValueKey('regular-settings')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('local-quick-output')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'actual Full Settings opens searchable icon library and returns to active controls',
    (tester) async {
      final harness = await mountRegular(tester);
      await tester.pumpWidget(SmartKeysApp(controller: harness.controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('regular-settings')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-list')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('open-app-icon-library')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-icon-library')), findsOneWidget);
      expect(find.byKey(const ValueKey('app-library-catalog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('icon-library-search')),
        'chrome',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('library-icon-chrome')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-list')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('regular-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('regular-touchpad')), findsOneWidget);
    },
  );
  testWidgets(
    'Launcher shows only Desktop-assigned slots in their saved order',
    (tester) async {
      final harness = await mountRegular(tester);
      final slots = List<String?>.filled(launcherSlotCount, null)
        ..[0] = 'chrome'
        ..[7] = 'chatgpt';
      harness.companion.syncedManifest.value = harness
          .companion
          .syncedManifest
          .value!
          .copyWith(launcherApplicationIds: slots);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('regular-cell-0')),
          matching: find.byKey(const ValueKey('regular-launch-chrome')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('regular-cell-7')),
          matching: find.byKey(const ValueKey('regular-launch-chatgpt')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('regular-launch-vscode')), findsNothing);
      harness.companion.syncedManifest.value = harness
          .companion
          .syncedManifest
          .value!
          .copyWith(
            launcherApplicationIds: List<String?>.filled(
              launcherSlotCount,
              null,
            ),
          );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('regular-configure-launchpad')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('regular-launch-chrome')), findsNothing);
      expect(find.byKey(const ValueKey('regular-cell-11')), findsOneWidget);
    },
  );

  testWidgets(
    'stale activation and successful HTTP response do not unlock app keys',
    (tester) async {
      final service = RecordingCompanionService();
      final harness = await mountRegular(tester, companion: service);
      final initial = service.syncedManifest.value!;
      service.syncedManifest.value = initial.copyWith(
        applicationActivationSequence: 5,
        activatedApplicationId: 'chrome',
        applications: [
          for (final app in initial.applications)
            app.copyWith(foreground: app.id == 'chrome'),
        ],
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('regular-button-chrome.newTab')),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
            .data,
        'Launchpad',
      );
      expect(find.textContaining('has not confirmed'), findsOneWidget);
      expect(harness.companion.remoteActions, hasLength(1));
    },
  );

  testWidgets(
    'returning to Launchpad ignores a later old activation notification',
    (tester) async {
      final service = RecordingCompanionService();
      await mountRegular(tester, companion: service);
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('regular-nav-launchpad')));
      await tester.pumpAndSettle();
      final current = service.syncedManifest.value!;
      service.syncedManifest.value = current.copyWith(
        applicationActivationSequence: 20,
        activatedApplicationId: 'chrome',
        applications: [
          for (final app in current.applications)
            app.copyWith(foreground: app.id == 'chrome'),
        ],
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
            .data,
        'Launchpad',
      );
      expect(
        find.byKey(const ValueKey('regular-button-chrome.newTab')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'foreground loss disables app shortcuts while General remains deliberate',
    (tester) async {
      final harness = await mountRegular(tester);
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pumpAndSettle();
      final current = harness.companion.syncedManifest.value!;
      harness.companion.syncedManifest.value = current.copyWith(
        applications: [
          for (final app in current.applications)
            app.copyWith(foreground: app.id == 'chatgpt'),
        ],
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InkWell>(
              find.byKey(const ValueKey('regular-button-chrome.newTab')),
            )
            .onTap,
        isNull,
      );
      expect(
        tester
            .widget<LocalDictationEntryButton>(
              find.byType(LocalDictationEntryButton),
            )
            .entryEnabled,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('regular-nav-general')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InkWell>(
              find.byKey(const ValueKey('regular-button-keyboard.copy')),
            )
            .onTap,
        isNotNull,
      );
    },
  );

  testWidgets('Launcher retains clock and Desktop media controls', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    connectRegularHarness(harness, manifest: DesktopManifest.regularStarter());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('regular-clock')), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('regular-system-keyboard.playPause')),
    );
    await tester.tap(
      find.byKey(const ValueKey('regular-system-keyboard.mute')),
    );
    await tester.pumpAndSettle();
    expect(harness.companion.remoteActions.map((action) => action.buttonId), [
      'keyboard.playPause',
      'keyboard.mute',
    ]);
  });

  testWidgets('launchpad renders twelve cells and launches Desktop IDs', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    expect(find.byKey(const ValueKey('regular-cell-11')), findsOneWidget);
    final grid = tester.widget<GridView>(
      find.byKey(const ValueKey('regular-twelve-key-grid')),
    );
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      4,
    );
    await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
    await tester.pumpAndSettle();
    expect(
      harness.companion.remoteActions.single.kind,
      RemoteActionKind.launchApplication,
    );
    expect(harness.companion.remoteActions.single.applicationId, 'chrome');
    expect(
      find.byKey(const ValueKey('regular-button-chrome.newTab')),
      findsOneWidget,
    );
    expect(harness.hid.pressedActions, isEmpty);
    expect(harness.hid.steppedActions, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'General is keyboard even when Desktop current profile is an app',
    (tester) async {
      final harness = await mountRegular(tester);
      final manifest = harness.companion.syncedManifest.value!;
      harness.companion.syncedManifest.value = manifest.copyWith(
        currentProfileId: 'browser',
        profiles: [
          ...manifest.profiles,
          const RemoteProfile(
            id: 'browser',
            name: 'Chrome',
            layoutId: 'app.chrome',
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('regular-nav-general')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('regular-button-keyboard.copy')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('regular-button-chrome.newTab')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('regular-button-keyboard.copy')),
      );
      await tester.pumpAndSettle();
      expect(harness.companion.remoteActions.single.buttonId, 'keyboard.copy');
    },
  );

  testWidgets('General sends only the close action synced by Desktop', (
    tester,
  ) async {
    final defaults = DesktopManifest.regularStarter();
    final windows = defaults.copyWith(
      layouts: [
        for (final layout in defaults.layouts)
          projectGeneralLayout(layout, RemoteShortcutPlatform.windows),
      ],
    );
    final harness = await mountRegular(tester, manifest: windows);
    await tester.tap(find.byKey(const ValueKey('regular-nav-general')));
    await tester.pumpAndSettle();
    final cell = find.byKey(const ValueKey('regular-cell-7'));
    final close = find.descendant(
      of: cell,
      matching: find.byKey(
        const ValueKey('regular-button-$generalCloseAppShortcutId'),
      ),
    );
    expect(
      find.descendant(of: close, matching: find.text('Close App')),
      findsOneWidget,
    );
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(
      harness.companion.remoteActions.single.buttonId,
      generalCloseAppShortcutId,
    );
    expect(harness.hid.pressedActions, isEmpty);

    final synced = harness.companion.syncedManifest.value!;
    final general = synced.layoutById('keyboard')!;
    final buttons = [...general.buttons]
      ..[7] = const RemoteShortcutButton(
        id: 'keyboard.escape',
        name: 'Escape',
        icon: 'close',
        targetType: RemoteTargetType.keyboardShortcut,
        shortcut: ['ESC'],
      );
    harness.companion.syncedManifest.value = synced.copyWith(
      layouts: [
        for (final layout in synced.layouts)
          layout.id == general.id ? general.copyWith(buttons: buttons) : layout,
      ],
    );
    await tester.pumpAndSettle();
    expect(close, findsNothing);
    expect(
      find.descendant(of: cell, matching: find.text('Escape')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('regular-button-keyboard.escape')),
    );
    await tester.pumpAndSettle();
    expect(harness.companion.remoteActions.last.buttonId, 'keyboard.escape');
  });

  testWidgets('custom layouts retain buttons beyond twelve through paging', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
    await tester.pumpAndSettle();
    final manifest = harness.companion.syncedManifest.value!;
    final old = manifest.layoutById('app.chrome')!;
    final custom = old.copyWith(
      buttons: List.generate(
        15,
        (index) => RemoteShortcutButton(
          id: 'custom.chrome.$index',
          name: 'Custom $index',
          icon: 'keyboard',
          targetType: RemoteTargetType.keyboardShortcut,
          shortcut: const ['PRIMARY', 'T'],
        ),
      ),
    );
    harness.companion.syncedManifest.value = manifest.copyWith(
      layouts: [
        for (final layout in manifest.layouts)
          layout.id == custom.id ? custom : layout,
      ],
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('regular-button-custom.chrome.11')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('regular-button-custom.chrome.12')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('regular-next-page')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('regular-button-custom.chrome.14')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('regular-button-custom.chrome.14')),
    );
    await tester.pumpAndSettle();
    expect(harness.companion.remoteActions.last.buttonId, 'custom.chrome.14');
  });

  testWidgets(
    'disconnect disables shortcuts pointer and Desktop dictation without HID fallback',
    (tester) async {
      final harness = await mountRegular(tester);
      harness.companion.status.value = CompanionSyncStatus.disconnected;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('regular-connect-desktop')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('regular-twelve-key-grid')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('regular-touchpad')), findsNothing);
      final entry = tester.widget<LocalDictationEntryButton>(
        find.byType(LocalDictationEntryButton),
      );
      expect(entry.entryEnabled, isFalse);
      expect(entry.forceDesktopOutput, isTrue);
      expect(harness.companion.remoteActions, isEmpty);
      expect(harness.hid.pressedActions, isEmpty);
    },
  );

  testWidgets('touchpad uses Desktop mouse capability and never local HID', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    final pad = find.byKey(const ValueKey('regular-touchpad'));
    expect(pad, findsOneWidget);
    await tester.tapAt(tester.getCenter(pad));
    await tester.pumpAndSettle();
    expect(harness.companion.pointerInputs.last.kind, PointerInputKind.button);
    expect(harness.hid.steppedActions, isEmpty);
    harness.companion.host.value = connectedCompanionHost;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('regular-touchpad')), findsNothing);
    expect(
      find.byKey(const ValueKey('regular-touchpad-unavailable')),
      findsOneWidget,
    );
  });

  testWidgets('native pointer errors are visible beside the regular touchpad', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    harness.companion.pointerErrors.value =
        'Desktop mouse input failed: pointer_permission_missing';
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('regular-desktop-pointer-error')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Accessibility and event posting'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'late launch completion cannot select an app on another computer',
    (tester) async {
      final companion = DeferredRegularCompanion();
      final harness = await mountRegular(tester, companion: companion);
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pump();
      expect(companion.remoteActions.single.applicationId, 'chrome');
      companion.host.value = connectedCompanionHost;
      await tester.pump();
      companion.launch.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
            .data,
        'Launchpad',
      );
      expect(
        find.byKey(const ValueKey('regular-button-chrome.newTab')),
        findsNothing,
      );
      expect(harness.hid.pressedActions, isEmpty);
    },
  );

  testWidgets(
    'a same-session reconnect invalidates an earlier pending launch',
    (tester) async {
      final companion = DeferredRegularCompanion();
      await mountRegular(tester, companion: companion);
      await tester.tap(find.byKey(const ValueKey('regular-launch-chrome')));
      await tester.pump();
      expect(companion.remoteActions.single.applicationId, 'chrome');
      companion.status.value = CompanionSyncStatus.disconnected;
      await tester.pump();
      companion.status.value = CompanionSyncStatus.ready;
      await tester.pump();
      companion.launch.complete();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('regular-workspace-title')))
            .data,
        'Launchpad',
      );
      expect(
        find.byKey(const ValueKey('regular-button-chrome.newTab')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'safe areas and large phone text keep four columns without overflow',
    (tester) async {
      final harness = await mountRegular(tester);
      tester.view.padding = const FakeViewPadding(left: 30, right: 18);
      tester.view.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(() {
        tester.view.resetPadding();
        tester.view.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await tester.pumpWidget(regularTestApp(harness));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final first = tester.getRect(
        find.byKey(const ValueKey('regular-cell-0')),
      );
      final fourth = tester.getRect(
        find.byKey(const ValueKey('regular-cell-3')),
      );
      final ninth = tester.getRect(
        find.byKey(const ValueKey('regular-cell-8')),
      );
      expect(fourth.top, first.top);
      expect(ninth.top, greaterThan(first.bottom));
    },
  );

  testWidgets('portrait windows gate controls and restore in landscape', (
    tester,
  ) async {
    final harness = await mountRegular(tester);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('regular-portrait-gate')), findsOneWidget);
    expect(find.byKey(const ValueKey('regular-twelve-key-grid')), findsNothing);
    expect(harness.companion.remoteActions, isEmpty);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('regular-twelve-key-grid')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
