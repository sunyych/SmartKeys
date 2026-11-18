import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lumiakey_bluetooth_lite/lite_controller.dart';
import 'package:lumiakey_bluetooth_lite/local_launcher.dart';
import 'package:lumiakey_bluetooth_lite/local_profiles.dart';

const hid = MethodChannel('smart_keys/hid');
const connectedA = {
  'status': 'connected',
  'activeHost': {'id': 'a', 'name': 'Test A', 'address': 'AA:BB:CC:DD:EE:01'},
  'pairedHosts': [
    {'id': 'a', 'name': 'Test A', 'address': 'AA:BB:CC:DD:EE:01'},
    {'id': 'b', 'name': 'Test B', 'address': 'AA:BB:CC:DD:EE:02'},
  ],
};
final connectedB = {
  ...connectedA,
  'activeHost': {'id': 'b', 'name': 'Test B', 'address': 'AA:BB:CC:DD:EE:02'},
};
const chord = LocalShortcut(
  title: 'Open app',
  keyCode: 'G',
  modifiers: ['LEFT_CTRL', 'LEFT_ALT'],
);
const slot = LocalLaunchSlot(
  title: 'ChatGPT',
  iconId: 'chatgpt',
  profileId: 'chatgpt',
  launchShortcut: chord,
);

class Profiles implements LocalProfileStore {
  List<LocalProfile> values = defaultLocalProfiles();
  bool failLoad = false, failSave = false;
  @override
  Future<List<LocalProfile>> load() async {
    if (failLoad) throw StateError('Load failed');
    return values;
  }

  @override
  Future<void> save(List<LocalProfile> values) async {
    if (failSave) throw StateError('Save failed');
    this.values = values;
  }
}

Future<void> emitSnapshot(Map<String, Object?> snapshot) {
  final delivered = Completer<void>();
  ServicesBinding.instance.channelBuffers.push(
    'smart_keys/hid',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('connectionSnapshotChanged', snapshot),
    ),
    (_) => delivered.complete(),
  );
  return delivered.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  FutureOr<Object?> Function(MethodCall)? reply;
  List<MethodCall> getInput() =>
      calls.where((call) => call.method == 'sendStep').toList();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    reply = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hid, (call) async {
          calls.add(call);
          if (reply != null) return await reply!(call);
          if (call.method == 'getAppMetadata') {
            return {'appVersion': '1.2.0', 'appBuild': 3};
          }
          return call.method == 'refreshPairedHosts' ||
                  call.method == 'sendStep'
              ? connectedA
              : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(hid, null),
  );

  Future<LiteController> ready({
    Profiles? profiles,
    MemoryLocalLauncherStore? launcher,
  }) async {
    final controller = LiteController(
      profileStore: profiles ?? Profiles(),
      launcherStore: launcher ?? MemoryLocalLauncherStore(),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.setLandscape(true);
    controller.setControlsVisible(true);
    return controller;
  }

  test(
    'default twelve slots and local profile navigation grant no launch input',
    () async {
      final controller = await ready();
      expect(controller.launcherSlots, hasLength(12));
      expect(controller.selectedProfileId, isNull);
      expect(controller.launcherSlots.take(2).map((s) => s.title), [
        'ChatGPT',
        'Chrome',
      ]);
      for (var index = 0; index < 12; index++) {
        expect(await controller.launchSlot(index), false);
      }
      controller.selectProfile('chatgpt');
      expect(controller.selectedProfileId, 'chatgpt');
      expect(getInput(), isEmpty);
    },
  );

  test(
    'a healthy Bluetooth snapshot clears only a prior connection failure',
    () async {
      final controller = await ready();
      await emitSnapshot({
        ...connectedA,
        'error': 'private connection failure',
      });
      expect(controller.error, contains('Bluetooth could not complete'));
      await emitSnapshot({...connectedA, 'error': null});
      expect(controller.connected, true);
      expect(controller.error, isNull);
    },
  );

  test(
    'successful Bluetooth refresh preserves configuration load and save failures',
    () async {
      final unread = Profiles()..failLoad = true;
      final loadFailed = await ready(profiles: unread);
      expect(loadFailed.error, contains('Could not load saved shortcuts'));
      await emitSnapshot({...connectedA, 'error': 'connection failure'});
      await emitSnapshot({...connectedA, 'error': null});
      expect(loadFailed.error, contains('Could not load saved shortcuts'));
      loadFailed.dispose();
      final store = Profiles();
      final saveFailed = await ready(profiles: store);
      store.failSave = true;
      await expectLater(
        saveFailed.saveProfile(saveFailed.profiles.first),
        throwsStateError,
      );
      await saveFailed.refreshPairedHosts();
      expect(saveFailed.error, contains('Could not save these settings'));
    },
  );

  test(
    'input failures survive healthy connection snapshots until successful input or dismissal',
    () async {
      final controller = await ready();
      var failInput = true;
      reply = (call) {
        if (call.method == 'sendStep' && failInput) {
          throw PlatformException(code: 'input-failed');
        }
        return call.method == 'refreshPairedHosts' || call.method == 'sendStep'
            ? connectedA
            : null;
      };
      expect(await controller.executeShortcut(chord), false);
      await controller.refreshPairedHosts();
      expect(controller.error, contains('could not send this input'));
      failInput = false;
      expect(await controller.executeShortcut(chord), true);
      expect(controller.error, isNull);
      failInput = true;
      expect(await controller.executeShortcut(chord), false);
      controller.clearError();
      expect(controller.error, isNull);
    },
  );

  test(
    'a durable launch sends its exact frozen combination and links a local profile',
    () async {
      final controller = await ready();
      final modifiers = ['LEFT_CTRL', 'LEFT_ALT'];
      await controller.saveLaunchSlot(
        0,
        LocalLaunchSlot(
          title: 'ChatGPT',
          profileId: 'chatgpt',
          launchShortcut: LocalShortcut(
            title: 'Launch',
            keyCode: 'G',
            modifiers: modifiers,
          ),
        ),
      );
      modifiers[0] = 'LEFT_SHIFT';
      expect(
        () => controller.launcherSlots.first.launchShortcut!.modifiers.add(
          'LEFT_META',
        ),
        throwsUnsupportedError,
      );
      expect(
        () => controller.profiles.first.shortcuts.clear(),
        throwsUnsupportedError,
      );
      expect(await controller.launchSlot(0), true);
      expect(getInput(), hasLength(1));
      expect(getInput().single.arguments, {
        'type': 'keyboard',
        'keyCode': 'G',
        'modifiers': ['LEFT_CTRL', 'LEFT_ALT'],
        'expectedHostAddress': 'AA:BB:CC:DD:EE:01',
      });
      expect(controller.selectedProfileId, 'chatgpt');
    },
  );

  test(
    'consumer controls use HID and cannot be registered as application launch authority',
    () async {
      final controller = await ready();
      final general = controller.profiles.first;
      expect(general.shortcuts.where((s) => s.isKeyboard), hasLength(6));
      expect(general.shortcuts.where((s) => s.isConsumer), hasLength(6));
      expect(await controller.sendConsumer('PLAY_PAUSE'), true);
      expect(getInput().single.arguments, {
        'type': 'consumerControl',
        'value': 'PLAY_PAUSE',
        'expectedHostAddress': 'AA:BB:CC:DD:EE:01',
      });
      expect(
        () => controller.saveLaunchSlot(
          0,
          const LocalLaunchSlot(
            title: 'Invalid',
            launchShortcut: LocalShortcut.consumer(
              title: 'Media',
              usage: 'PLAY_PAUSE',
            ),
          ),
        ),
        throwsFormatException,
      );
      expect(await controller.sendConsumer('UNKNOWN'), false);
    },
  );

  test(
    'linked profile selection and context release wait for completed native input acknowledgement',
    () async {
      final controller = await ready();
      await controller.saveLaunchSlot(0, slot);
      final acknowledged = Completer<Object?>();
      reply = (call) => call.method == 'sendStep' ? acknowledged.future : null;
      final releases = calls
          .where((call) => call.method == 'releaseAllKeys')
          .length;
      final pending = controller.launchSlot(0);
      expect(controller.selectedProfileId, isNull);
      expect(controller.pendingLaunchSlot, 0);
      expect(
        calls.where((call) => call.method == 'releaseAllKeys'),
        hasLength(releases),
      );
      acknowledged.complete(connectedA);
      expect(await pending, true);
      expect(controller.selectedProfileId, 'chatgpt');
      expect(
        calls.where((call) => call.method == 'releaseAllKeys'),
        hasLength(releases + 1),
      );
    },
  );

  for (final state in ['disconnected', 'portrait', 'background', 'settings']) {
    test(
      '$state blocks keyboard media pointer and configured launch without sending input',
      () async {
        final controller = await ready();
        await controller.saveLaunchSlot(0, slot);
        switch (state) {
          case 'disconnected':
            await emitSnapshot({
              ...connectedA,
              'status': 'disconnected',
              'activeHost': null,
            });
          case 'portrait':
            controller.setLandscape(false);
          case 'background':
            controller.handleLifecycle(AppLifecycleState.paused);
          case 'settings':
            controller.setControlsVisible(false);
        }
        expect(await controller.executeShortcut(chord), false);
        expect(await controller.sendConsumer('MUTE'), false);
        expect(await controller.movePointer(const Offset(30, 10)), false);
        expect(await controller.scrollPointer(48), false);
        expect(await controller.primaryClick(), false);
        expect(await controller.secondaryClick(), false);
        expect(await controller.launchSlot(0), false);
        expect(getInput(), isEmpty);
      },
    );
  }

  test(
    'an obsolete pointer epoch and incomplete scroll remainder cannot survive context changes',
    () async {
      final controller = await ready();
      final old = controller.inputEpoch;
      expect(await controller.scrollPointer(12, epoch: old), true);
      await controller.releaseInput();
      expect(
        await controller.movePointer(const Offset(10, 10), epoch: old),
        false,
      );
      expect(await controller.primaryClick(epoch: old), false);
      expect(await controller.scrollPointer(12), true);
      expect(getInput(), isEmpty);
      expect(await controller.scrollPointer(12), true);
      expect(getInput().single.arguments, containsPair('value', '-1'));
    },
  );

  for (final change in [
    'host',
    'settings',
    'page',
    'background',
    'slot',
    'deleteProfile',
  ]) {
    test(
      'pending launch completion after $change cannot navigate or report success',
      () async {
        final controller = await ready();
        await controller.saveLaunchSlot(0, slot);
        final accepted = Completer<Object?>();
        reply = (call) => call.method == 'sendStep' ? accepted.future : null;
        final pending = controller.launchSlot(0);
        expect(getInput(), hasLength(1));
        switch (change) {
          case 'host':
            await emitSnapshot(connectedB);
          case 'settings':
            controller.setControlsVisible(false);
          case 'page':
            await controller.releaseInput();
          case 'background':
            controller.handleLifecycle(AppLifecycleState.paused);
          case 'slot':
            await controller.saveLaunchSlot(
              0,
              const LocalLaunchSlot(title: 'ChatGPT'),
            );
          case 'deleteProfile':
            await controller.deleteProfile('chatgpt');
        }
        accepted.complete(connectedA);
        expect(await pending, false);
        expect(controller.selectedProfileId, isNull);
        if (change == 'host') expect(controller.activeHost!.id, 'b');
      },
    );
  }

  test(
    'a listener changing context before dispatch prevents launch input entirely',
    () async {
      final controller = await ready();
      await controller.saveLaunchSlot(0, slot);
      controller.addListener(() {
        if (controller.pendingLaunchSlot != null) {
          controller.setControlsVisible(false);
        }
      });
      expect(await controller.launchSlot(0), false);
      expect(getInput(), isEmpty);
    },
  );

  test(
    'failed native launch never changes local profile or reports success',
    () async {
      final controller = await ready();
      await controller.saveLaunchSlot(0, slot);
      reply = (call) {
        if (call.method == 'sendStep') {
          throw PlatformException(code: 'rejected', message: 'private-path');
        }
        return null;
      };
      expect(await controller.launchSlot(0), false);
      expect(controller.selectedProfileId, isNull);
      expect(controller.error, isNot(contains('private-path')));
    },
  );

  for (final change in ['host', 'background']) {
    test(
      'a late native failure after $change cannot overwrite the new context or log a cancelled input',
      () async {
        final controller = await ready();
        final late = Completer<Object?>();
        reply = (call) => call.method == 'sendStep' ? late.future : null;
        final pending = controller.executeShortcut(chord);
        if (change == 'host') {
          await emitSnapshot(connectedB);
        } else {
          controller.handleLifecycle(AppLifecycleState.paused);
        }
        final before = controller.error;
        late.completeError(
          PlatformException(code: 'cancelled', message: 'old-private-failure'),
        );
        expect(await pending, false);
        await controller.diagnostics.settled;
        expect(controller.error, before);
        expect(controller.diagnostics.journal.events, isEmpty);
        if (change == 'host') expect(controller.activeHost!.id, 'b');
      },
    );
  }

  test(
    'an obsolete connection failure cannot overwrite a newer connected snapshot',
    () async {
      final controller = await ready();
      final old = Completer<Object?>();
      var reads = 0;
      reply = (call) => call.method == 'refreshPairedHosts'
          ? ++reads == 1
                ? old.future
                : connectedB
          : null;
      final obsolete = controller.refreshPairedHosts();
      expect(await controller.refreshPairedHosts(), true);
      old.completeError(
        PlatformException(code: 'cancelled', message: 'old failure'),
      );
      expect(await obsolete, false);
      await controller.diagnostics.settled;
      expect(controller.activeHost!.id, 'b');
      expect(controller.error, isNull);
      expect(controller.diagnostics.journal.events, isEmpty);
    },
  );

  test(
    'an obsolete connection success cannot roll back a newer host or report success',
    () async {
      final controller = await ready();
      final old = Completer<Object?>();
      var reads = 0;
      reply = (call) => call.method == 'refreshPairedHosts'
          ? ++reads == 1
                ? old.future
                : connectedB
          : null;
      final obsolete = controller.refreshPairedHosts();
      expect(await controller.refreshPairedHosts(), true);
      old.complete(connectedA);
      expect(await obsolete, false);
      expect(controller.activeHost!.id, 'b');
    },
  );

  test(
    'failed persistence and failed loads cannot publish or overwrite launch authority',
    () async {
      final store = MemoryLocalLauncherStore();
      final controller = await ready(launcher: store);
      store.failSave = true;
      await expectLater(controller.saveLaunchSlot(0, slot), throwsStateError);
      expect(controller.launcherSlots.first.configured, false);
      expect(await controller.launchSlot(0), false);
      expect(getInput(), isEmpty);
      final prior = defaultLocalLauncherSlots()..[0] = slot;
      final unread = MemoryLocalLauncherStore()
        ..slots = prior
        ..failLoad = true;
      final failed = await ready(launcher: unread);
      await expectLater(
        failed.saveLaunchSlot(0, const LocalLaunchSlot(title: 'Replacement')),
        throwsStateError,
      );
      expect(unread.slots.first.configured, true);
    },
  );

  test(
    'serialized profile writes preserve existing fifteen-key data and failed edits',
    () async {
      final old = LocalProfile(
        id: 'custom',
        name: 'Saved',
        shortcuts: List.filled(15, chord),
      );
      final store = Profiles()..values = [old];
      final controller = await ready(profiles: store);
      expect(controller.profiles.single.shortcuts, hasLength(15));
      store.failSave = true;
      await expectLater(
        controller.saveProfile(old.copyWith(name: 'Unsaved')),
        throwsStateError,
      );
      expect(controller.profiles.single.name, 'Saved');
      store.failSave = false;
      await Future.wait([
        controller.saveProfile(
          const LocalProfile(id: 'one', name: 'One', shortcuts: []),
        ),
        controller.saveProfile(
          const LocalProfile(id: 'two', name: 'Two', shortcuts: []),
        ),
      ]);
      expect(controller.profiles.map((p) => p.id), ['custom', 'one', 'two']);
    },
  );

  test(
    'launcher persistence is separate from profiles and rejects corrupt or executable payloads',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        SharedPreferencesProfileStore.storageKey,
        'existing-profile-data',
      );
      final values = defaultLocalLauncherSlots()..[0] = slot;
      await const SharedPreferencesLauncherStore().save(values);
      final reloaded = await const SharedPreferencesLauncherStore().load();
      expect(reloaded.first.launchShortcut!.keyCode, 'G');
      expect(
        prefs.getString(SharedPreferencesProfileStore.storageKey),
        'existing-profile-data',
      );
      expect(
        () => LocalLaunchSlot.fromJson({
          ...slot.toJson(),
          'executable': '/private/app',
        }),
        throwsFormatException,
      );
      await prefs.setString(
        SharedPreferencesLauncherStore.storageKey,
        '{broken',
      );
      await expectLater(
        const SharedPreferencesLauncherStore().load(),
        throwsFormatException,
      );
      expect(
        prefs.getString(SharedPreferencesLauncherStore.storageKey),
        '{broken',
      );
      expect(jsonEncode(slot.toJson()), isNot(contains('sendStep')));
    },
  );
}
