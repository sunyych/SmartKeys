import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';
import 'package:lumiakeys_companion/desktop_actions.dart';
import 'package:lumiakeys_companion/desktop_controller.dart';
import 'package:lumiakeys_companion/shortcut_transfer_service.dart';

class _Discovery implements ApplicationDiscovery {
  @override
  Future<List<RemoteApplication>> refresh(List<RemoteApplication> apps) async =>
      apps;
}

class _BrokenStore extends MemoryDesktopConfigStore {
  @override
  Future<DesktopManifest?> load() async =>
      throw const FormatException('broken settings');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('load failure also falls back to compact production defaults', () async {
    final controller = DesktopController(
      store: _BrokenStore(),
      discovery: _Discovery(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    expect(controller.error, isNotNull);
    expect(
      controller.manifestForExport.layouts.every(
        (layout) => layout.id == 'chatgpt' || layout.buttons.length <= 12,
      ),
      isTrue,
    );
    expect(
      controller.manifestForExport.layoutById('keyboard')!.buttons,
      hasLength(12),
    );
  });
  test(
    'production initialization persists twelve-key Regular defaults',
    () async {
      final store = MemoryDesktopConfigStore();
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(controller.error, isNull);
      expect(store.value!.layoutById('keyboard')!.buttons, hasLength(12));
      expect(
        store.value!.layoutById('chatgpt')!.buttons.length,
        greaterThan(12),
      );
      expect(store.value!.layoutById('app.chrome')!.buttons, hasLength(12));
      expect(
        store.value!.layouts.every(
          (layout) => layout.id == 'chatgpt' || layout.buttons.length <= 12,
        ),
        isTrue,
      );
      final reloaded = DesktopController(store: store, discovery: _Discovery());
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(
        store.value!.layoutById('chatgpt')!.buttons.length,
        greaterThan(12),
      );
    },
  );
  test(
    'unedited old defaults migrate without retaining old overflow',
    () async {
      final store = MemoryDesktopConfigStore()
        ..value = DesktopManifest.starter();
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(
        store.value!.layouts.every(
          (layout) => layout.id == 'chatgpt' || layout.buttons.length <= 12,
        ),
        isTrue,
      );
      expect(store.value!.buttonById('keyboard.volumeUp'), isNotNull);
    },
  );
  test(
    'custom bindings, reordered buttons and overflow survive migration',
    () async {
      final old = DesktopManifest.starter();
      final chrome = old.layoutById('app.chrome')!;
      final customButtons = chrome.buttons.reversed
          .map(
            (button) => button.id == 'chrome.copy'
                ? button.copyWith(name: 'My Copy', shortcut: const ['ALT', 'C'])
                : button,
          )
          .toList();
      final store = MemoryDesktopConfigStore()
        ..value = old.copyWith(
          layouts: old.layouts
              .map(
                (layout) => layout.id == chrome.id
                    ? layout.copyWith(buttons: customButtons)
                    : layout,
              )
              .toList(),
        );
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final saved = store.value!.layoutById('app.chrome')!;
      expect(
        saved.buttons.map((button) => button.id),
        customButtons.map((button) => button.id),
      );
      expect(saved.buttons, hasLength(15));
      expect(
        saved.buttons
            .singleWhere((button) => button.id == 'chrome.copy')
            .shortcut,
        ['ALT', 'C'],
      );
      expect(
        saved.buttons.singleWhere((button) => button.id == 'chrome.copy').name,
        'My Copy',
      );
    },
  );
  test(
    'old twelve-key ChatGPT layout and Codex profile merge without data loss',
    () async {
      final old = DesktopManifest.starter();
      final chatGpt = old.layoutById('chatgpt')!;
      const oldIds = [
        'chatgpt.newChat',
        'chatgpt.codex.send',
        'chatgpt.codex.copy',
        'chatgpt.codex.paste',
        'chatgpt.codex.cut',
        'chatgpt.codex.focusInput',
        'chatgpt.codex.backspace',
        'chatgpt.codex.alternateSend',
        'chatgpt.find',
        'chatgpt.sidebar',
        'chatgpt.chatView',
        'chatgpt.codexMode',
      ];
      final savedChatGpt = chatGpt.copyWith(
        buttons: [
          for (final id in oldIds)
            if (id == 'chatgpt.codex.send')
              old.buttonById(id)!.copyWith(shortcut: const ['ALT', 'S'])
            else
              old.buttonById(id)!,
        ],
      );
      final legacyCodex = old
          .layoutById('codex')!
          .copyWith(
            buttons: [
              old
                  .buttonById('codex.send')!
                  .copyWith(shortcut: const ['ALT', 'K']),
              const RemoteShortcutButton(
                id: 'my.unique',
                name: 'My unique action',
                icon: 'star',
                targetType: RemoteTargetType.keyboardShortcut,
                shortcut: ['ALT', 'F9'],
              ),
            ],
          );
      final store = MemoryDesktopConfigStore()
        ..value = old.copyWith(
          layouts: [
            for (final layout in old.layouts)
              switch (layout.id) {
                'chatgpt' => savedChatGpt,
                'codex' => legacyCodex,
                _ => layout,
              },
          ],
          profiles: [
            ...old.profiles,
            const RemoteProfile(
              id: 'my-profile',
              name: 'My old Codex setup',
              layoutId: 'vibe.codex',
            ),
          ],
          currentProfileId: 'my-profile',
        );
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      final manifest = controller.manifestForExport;
      manifest.validate();
      final merged = manifest.layoutById('chatgpt')!;
      expect(merged.buttons.map((button) => button.id), containsAll(oldIds));
      expect(merged.buttons.map((button) => button.id), contains('my.unique'));
      expect(manifest.buttonById('chatgpt.codex.send')!.shortcut, ['ALT', 'S']);
      expect(manifest.buttonById('chatgpt.legacy.codex.codex.send')!.shortcut, [
        'ALT',
        'K',
      ]);
      expect(manifest.layoutById('codex'), isNull);
      expect(manifest.layoutById('vibe.codex'), isNull);
      expect(manifest.currentProfile!.layoutId, 'chatgpt');
      expect(manifest.currentProfile!.name, 'My old Codex setup');
      final saved = manifest.toJson();
      final reloaded = DesktopController(store: store, discovery: _Discovery());
      addTearDown(reloaded.dispose);
      await reloaded.initialize();
      expect(reloaded.manifestForExport.toJson(), saved);
    },
  );

  test(
    'legacy release flags cannot reorder or refill custom Chrome and ChatGPT boards',
    () async {
      final old = DesktopManifest.starter();
      final customLayouts = [
        for (final id in ['app.chrome', 'chatgpt'])
          old
              .layoutById(id)!
              .copyWith(
                buttons: old
                    .layoutById(id)!
                    .buttons
                    .reversed
                    .take(5)
                    .map(
                      (button) => button.copyWith(
                        name: 'Mine: ${button.name}',
                        shortcut:
                            button.targetType ==
                                RemoteTargetType.keyboardShortcut
                            ? const ['ALT', 'F9']
                            : button.shortcut,
                      ),
                    )
                    .toList(),
              ),
      ];
      final store = MemoryDesktopConfigStore()
        ..value = old.copyWith(
          applications: [
            ...old.applications,
            const RemoteApplication(
              id: 'codex',
              name: 'Legacy',
              icon: 'code',
              executable: 'ChatGPT',
              layoutId: 'codex',
            ),
          ],
          profiles: [
            ...old.profiles,
            const RemoteProfile(
              id: 'windows',
              name: 'Old Windows',
              layoutId: 'keyboard',
            ),
          ],
          layouts: old.layouts
              .map(
                (layout) => layout.id == 'codex'
                    ? layout.copyWith(
                        buttons: [
                          ...layout.buttons,
                          const RemoteShortcutButton(
                            id: 'user.unique',
                            name: 'Saved custom key',
                            icon: 'keyboard',
                            targetType: RemoteTargetType.keyboardShortcut,
                            shortcut: ['ALT', 'Q'],
                          ),
                        ],
                      )
                    : customLayouts
                              .where((custom) => custom.id == layout.id)
                              .firstOrNull ??
                          layout,
              )
              .toList(),
        );
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      for (final custom in customLayouts) {
        final saved = store.value!.layoutById(custom.id)!;
        if (custom.id == 'chatgpt') {
          expect(
            saved.buttons
                .take(custom.buttons.length)
                .map((button) => button.toJson()),
            custom.buttons.map((button) => button.toJson()),
          );
          expect(
            saved.buttons.any(
              (button) => button.id == chatGptFastModeShortcutId,
            ),
            isTrue,
          );
        } else {
          expect(saved.toJson(), custom.toJson(), reason: custom.id);
        }
      }
      store.value!.validate();
      expect(store.value!.buttonById('user.unique')!.name, 'Saved custom key');
      expect(
        store.value!
            .layoutById('chatgpt')!
            .buttons
            .any((button) => button.id == 'user.unique'),
        isTrue,
      );
    },
  );
  test(
    'a user-trimmed two-key board is preserved without legacy release evidence',
    () async {
      final old = DesktopManifest.starter();
      final chrome = old.layoutById('app.chrome')!;
      final custom = chrome.copyWith(buttons: chrome.buttons.take(2).toList());
      final store = MemoryDesktopConfigStore()
        ..value = old.copyWith(
          layouts: old.layouts
              .map((layout) => layout.id == custom.id ? custom : layout)
              .toList(),
        );
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(store.value!.layoutById(custom.id)!.toJson(), custom.toJson());
    },
  );
  test(
    'known native Apple defaults compact while edited Apple bindings remain intact',
    () async {
      final old = DesktopManifest.starter();
      RemoteShortcutLayout apple(RemoteShortcutLayout layout) =>
          layout.copyWith(
            buttons: layout.buttons
                .map(
                  (button) => button.copyWith(
                    shortcut: resolvePrimaryShortcut(
                      button.shortcut,
                      RemoteShortcutPlatform.apple,
                    ),
                  ),
                )
                .toList(),
          );
      final appleDefaults = old.copyWith(
        layouts: old.layouts.map(apple).toList(),
      );
      final store = MemoryDesktopConfigStore()..value = appleDefaults;
      final controller = DesktopController(
        store: store,
        discovery: _Discovery(),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(store.value!.layoutById('app.chrome')!.buttons, hasLength(12));
      expect(
        store.value!.layoutById('chatgpt')!.buttons.length,
        greaterThan(12),
      );
      final custom = apple(old.layoutById('app.chrome')!).copyWith(
        buttons: apple(old.layoutById('app.chrome')!).buttons
            .map(
              (button) => button.id == 'chrome.copy'
                  ? button.copyWith(shortcut: const ['COMMAND', 'SHIFT', 'C'])
                  : button,
            )
            .toList(),
      );
      final customStore = MemoryDesktopConfigStore()
        ..value = appleDefaults.copyWith(
          layouts: appleDefaults.layouts
              .map((layout) => layout.id == custom.id ? custom : layout)
              .toList(),
        );
      final customController = DesktopController(
        store: customStore,
        discovery: _Discovery(),
      );
      addTearDown(customController.dispose);
      await customController.initialize();
      expect(
        customStore.value!.layoutById(custom.id)!.toJson(),
        custom.toJson(),
      );
    },
  );
  test(
    'portable export/import accepts only the four fixed General media actions',
    () {
      const transfer = DesktopShortcutTransferService();
      final defaults = DesktopManifest.regularStarter();
      final restored = transfer.decode(transfer.encode(defaults));
      expect(
        restored.singleWhere((layout) => layout.id == 'keyboard').buttons,
        hasLength(12),
      );
      final bad = defaults.copyWith(
        layouts: defaults.layouts
            .map(
              (layout) => layout.id == 'keyboard'
                  ? layout.copyWith(
                      buttons: layout.buttons
                          .map(
                            (button) => button.id == 'keyboard.mute'
                                ? button.copyWith(target: 'volumeUp')
                                : button,
                          )
                          .toList(),
                    )
                  : layout,
            )
            .toList(),
      );
      expect(
        () => transfer.decode(transfer.encode(bad)),
        throwsFormatException,
      );
    },
  );
  const channel = MethodChannel('lumiakeys/test_regular_media');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test(
    'General dispatches only fixed native media methods without payloads',
    () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
      for (final platform in [TargetPlatform.windows, TargetPlatform.macOS]) {
        calls.clear();
        final actions = DesktopActions(
          mediaChannel: channel,
          platformOverride: platform,
        );
        final manifest = DesktopManifest.regularStarter();
        for (final action in ['mute', 'volumeDown', 'volumeUp', 'playPause']) {
          await actions.executeButton(
            manifest.buttonById('keyboard.$action')!,
            manifest,
          );
        }
        expect(calls.map((call) => call.method), [
          'toggleOutputMute',
          'volumeDown',
          'volumeUp',
          'playPause',
        ]);
        expect(calls.every((call) => call.arguments == null), isTrue);
        final mute = manifest.buttonById('keyboard.mute')!;
        await expectLater(
          actions.executeButton(mute.copyWith(target: 'volumeUp'), manifest),
          throwsFormatException,
        );
        await expectLater(
          actions.executeButton(mute, manifest, expectedAppId: 'chatgpt'),
          throwsFormatException,
        );
        expect(calls, hasLength(4));
      }
    },
  );
}
