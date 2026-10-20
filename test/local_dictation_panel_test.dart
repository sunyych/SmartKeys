import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_dictation/local_dictation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_keys/services/companion_service.dart';
import 'package:smart_keys/services/hid_service.dart';
import 'package:smart_keys/services/hid_text_output_service.dart';
import 'package:smart_keys/models/config.dart';
import 'package:smart_keys/ui/dictation_entry_consent.dart';
import 'package:smart_keys/ui/local_dictation_panel.dart';
import 'package:smart_keys/ui/local_dictation_route_observer.dart';

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first use explains both entries and does not open the microphone',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open-local-dictation'),
                onPressed: () => ensureDictationEntryExplained(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-local-dictation')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictation-entry-explanation')),
        findsOneWidget,
      );
      expect(find.text('Application voice input'), findsOneWidget);
      expect(find.text('Local quick dictation'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('dictation-explanation-cancel')),
      );
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(dictationConsentPreferenceKey), isNot(true));
      hid.dispose();
    },
  );

  testWidgets(
    'acknowledgement persists and panel stays ready in both orientations',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture();
      final manager = _FakeModelManager();
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const ValueKey('open'),
                onPressed: () => ensureDictationEntryExplained(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('dictation-explanation-accept')),
      );
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(dictationConsentPreferenceKey), isTrue);
      tester.view.resetPhysicalSize();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      tester.view.physicalSize = const Size(915, 412);
      final hid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              modelManager: manager,
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-dictation-panel')),
        findsOneWidget,
      );
      expect(find.text('English (fixed)'), findsOneWidget);
      expect(find.byKey(const ValueKey('dictation-language')), findsNothing);
      expect(
        find.byKey(const ValueKey('dictation-output-mode')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dictation-model')), findsOneWidget);
      expect(find.byKey(const ValueKey('start-dictation')), findsOneWidget);
      expect(tester.takeException(), isNull);
      hid.dispose();
      tester.view.resetPhysicalSize();
    },
  );

  testWidgets(
    'legacy language and HexNumpad preferences migrate to Bluetooth English',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'dictation.language.v1': 'chinese',
        'dictation.text_profile.v1': 'windowsHexNumpad',
      });
      final hid = _readyHid();
      var configuredLanguage = DictationLanguage.chinese;
      final capture = _FakeCapture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, language) async {
                configuredLanguage = language;
                return _FakeRecognizer();
              },
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('dictation-text-profile')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('dictation-language')), findsNothing);
      expect(find.text('English (fixed)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(configuredLanguage, DictationLanguage.english);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dictation.language.v1'), 'english');
      expect(prefs.getString('dictation.text_profile.v1'), 'usAscii');
      expect(prefs.getString('dictation.output_mode.v1'), 'bluetoothEnglish');
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      hid.dispose();
    },
  );

  testWidgets(
    'desktop multilingual output sends finalized Chinese text without HID',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hid = RecordingHidService();
      final companion = RecordingCompanionService()
        ..host.value = _dictationHost();
      final capture = _FakeCapture();
      var configuredLanguage = DictationLanguage.english;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              companion: companion,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, language) async {
                configuredLanguage = language;
                return _FakeRecognizer(text: '你好世界');
              },
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-output-mode')),
      );
      await tester.tap(find.text('LumiaKey Desktop · multilingual').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dictation-language')), findsOneWidget);
      expect(find.textContaining('sends finalized text'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('start-dictation')).evaluate().single.widget,
        isA<FilledButton>().having(
          (button) => button.onPressed,
          'onPressed',
          isNotNull,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(configuredLanguage, DictationLanguage.chinese);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('stop-dictation')))
            .onPressed,
        isNotNull,
        reason: 'Stop remains available while desktop dictation is listening',
      );
      final modeField = tester
          .widget<DropdownButtonFormField<DictationOutputMode>>(
            find.byKey(const ValueKey('dictation-output-mode')),
          );
      expect(
        modeField.onChanged,
        isNull,
        reason: 'output mode cannot change while busy',
      );
      capture.audio.add(
        List<int>.generate(3200, (index) => index.isEven ? 16 : 39),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      for (
        var frame = 0;
        frame < 20 && companion.dictationRequests.isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(companion.dictationRequests, hasLength(1));
      expect(companion.dictationRequests.single.text, '你好世界');
      expect(companion.dictationRequests.single.sequence, 0);
      expect(hid.textBatches, isEmpty);
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(capture.startCount, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      for (var frame = 0; frame < 20 && capture.stopCount < 2; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(
        capture.stopCount,
        2,
        reason: 'backgrounding cancels desktop capture',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      hid.dispose();
      companion.dispose();
    },
  );

  testWidgets(
    'desktop mode disables start without companion capability and cancels on host change',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hid = RecordingHidService();
      final companion = RecordingCompanionService()
        ..host.value = const CompanionHost(
          name: 'PC',
          platform: 'windows',
          address: '192.168.1.20',
          port: 45833,
          token: 'test-token',
        );
      final capture = _FakeCapture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              companion: companion,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(text: '你好'),
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-output-mode')),
      );
      await tester.tap(find.text('LumiaKey Desktop · multilingual').last);
      await tester.pumpAndSettle();
      final unavailableButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('start-dictation')),
      );
      expect(unavailableButton.onPressed, isNull);
      expect(capture.startCount, 0);

      companion.host.value = _dictationHost();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(
        capture.startCount,
        1,
        reason: 'desktop mode does not require Bluetooth',
      );
      companion.host.value = null;
      companion.host.value =
          _dictationHost(); // ABA still invalidates the pinned session.
      for (var frame = 0; frame < 20 && capture.stopCount == 0; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(capture.stopCount, 1);
      expect(companion.dictationRequests, isEmpty);
      expect(hid.textBatches, isEmpty);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      hid.dispose();
      companion.dispose();
    },
  );

  testWidgets(
    'desktop modifier busy skips one phrase and continues without HID fallback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hid = RecordingHidService();
      final companion = _BusyOnceCompanion()..host.value = _dictationHost();
      final capture = _FakeCapture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              companion: companion,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(text: '你好'),
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-output-mode')),
      );
      await tester.tap(find.text('LumiaKey Desktop · multilingual').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();

      Future<void> finalizePhrase() async {
        capture.audio.add(
          List<int>.generate(6400, (index) => index.isEven ? 0x10 : 0x27),
        );
        await tester.pump(const Duration(milliseconds: 20));
        capture.audio.add(List<int>.filled(32000, 0));
        for (var frame = 0; frame < 40 && companion.attempts < 1; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
      }

      await finalizePhrase();
      expect(companion.attempts, 1);
      expect(capture.stopCount, 0);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('stop-dictation')))
            .onPressed,
        isNotNull,
        reason: 'a preflight modifier conflict leaves capture listening',
      );
      expect(hid.textBatches, isEmpty, reason: 'no HID fallback is allowed');
      expect(
        find.textContaining('This phrase was skipped; dictation continues'),
        findsOneWidget,
      );

      capture.audio.add(
        List<int>.generate(6400, (index) => index.isEven ? 0x10 : 0x27),
      );
      await tester.pump(const Duration(milliseconds: 20));
      capture.audio.add(List<int>.filled(32000, 0));
      for (var frame = 0; frame < 40 && companion.attempts < 2; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(companion.attempts, 2);
      expect(companion.dictationRequests, hasLength(1));
      expect(companion.dictationRequests.single.text, '你好');
      expect(companion.dictationRequests.single.sequence, 1);
      expect(capture.stopCount, 0);
      expect(hid.textBatches, isEmpty);

      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      hid.dispose();
      companion.dispose();
    },
  );

  testWidgets(
    'desktop delivery failure stops capture and never replays or falls back',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hid = RecordingHidService();
      final companion = _PartialRejectingCompanion()
        ..host.value = _dictationHost();
      final capture = _FakeCapture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              companion: companion,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(text: '你好'),
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-output-mode')),
      );
      await tester.tap(find.text('LumiaKey Desktop · multilingual').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      capture.audio.add(
        List<int>.generate(
          35200,
          (index) => index < 3200 ? (index.isEven ? 16 : 39) : 0,
        ),
      );
      for (var frame = 0; frame < 30 && companion.attempts == 0; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      await tester.pumpAndSettle();
      expect(companion.attempts, 1);
      expect(companion.dictationRequests, hasLength(1));
      expect(capture.stopCount, 1);
      expect(
        find.textContaining('Desktop text delivery failed; dictation stopped'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('start-dictation')), findsOneWidget);
      expect(hid.textBatches, isEmpty);
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(
        companion.attempts,
        1,
        reason: 'failed final text is never replayed',
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      hid.dispose();
      companion.dispose();
    },
  );

  testWidgets(
    'entry owner prevents duplicate overlays and closes capture with its route',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        dictationConsentPreferenceKey: true,
      });
      final hid = _readyHid();
      final capture = _FakeCapture();
      var wakeLockEnabled = 0;
      var wakeLockDisabled = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [localDictationRouteObserver],
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: TextButton(
                    key: const ValueKey('underlying-home-shortcut'),
                    onPressed: () => hid.sendPress(
                      const HidAction(
                        type: ActionType.keyboard,
                        keyCode: 'KEY_A',
                      ),
                    ),
                    child: const Text('Home shortcut'),
                  ),
                ),
                Positioned.fill(
                  child: LocalDictationEntryButton(
                    hid: hid,
                    modelManager: _FakeModelManager(),
                    capture: capture,
                    recognizerFactory: (_, _) async => _FakeRecognizer(),
                    enableWakeLock: () async => wakeLockEnabled++,
                    disableWakeLock: () async => wakeLockDisabled++,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('local-quick-output')));
      await tester.tap(find.byKey(const ValueKey('local-quick-output')));
      await tester.pumpAndSettle();
      for (var frame = 0; frame < 30 && capture.startCount == 0; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(capture.startCount, 1);
      expect(wakeLockEnabled, 1);
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dictation-entry-barrier')),
        findsNothing,
      );

      final homeNavigator = Navigator.of(
        tester.element(find.byKey(const ValueKey('local-quick-output'))),
      );
      expect(await homeNavigator.maybePop(), isTrue);
      await tester.pumpAndSettle();
      for (
        var frame = 0;
        frame < 30 && (capture.stopCount < 1 || wakeLockDisabled < 1);
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(find.text('Home shortcut'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsNothing,
      );
      expect(capture.stopCount, 1, reason: 'Back closes entry before home');
      expect(wakeLockDisabled, 1, reason: 'Back releases wake lock');

      await tester.tap(find.byKey(const ValueKey('local-quick-output')));
      await tester.pumpAndSettle();
      for (var frame = 0; frame < 30 && capture.startCount < 2; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsOneWidget,
      );
      expect(
        capture.startCount,
        2,
        reason: 'entry can reopen after Back closes it',
      );

      await tester.tap(find.byKey(const ValueKey('underlying-home-shortcut')));
      await tester.pumpAndSettle();
      expect(hid.pressedActions, hasLength(1));
      expect(capture.stopCount, 1);

      unawaited(
        Navigator.of(
          tester.element(find.byKey(const ValueKey('local-quick-output'))),
        ).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Settings route')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (
        var frame = 0;
        frame < 30 && (capture.stopCount < 2 || wakeLockDisabled < 2);
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(capture.stopCount, 2, reason: 'covering route stops capture');
      expect(wakeLockDisabled, 2, reason: 'route stop releases wake lock');
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsNothing,
      );
      Navigator.of(tester.element(find.text('Settings route'))).pop();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsNothing,
      );
      expect(capture.startCount, 2, reason: 'return does not restart capture');
      expect(
        await homeNavigator.maybePop(),
        isFalse,
        reason: 'page navigation removed the old local-history entry',
      );

      await tester.tap(find.byKey(const ValueKey('local-quick-output')));
      await tester.pumpAndSettle();
      for (var frame = 0; frame < 30 && capture.startCount < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(capture.startCount, 3, reason: 'entry can be opened again');
      expect(wakeLockEnabled, 3);
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsOneWidget,
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      for (
        var frame = 0;
        frame < 30 && (capture.stopCount < 3 || wakeLockDisabled < 3);
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(capture.stopCount, 3, reason: 'home disposal closes microphone');
      expect(wakeLockDisabled, 3, reason: 'home disposal releases wake lock');
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsNothing,
      );
      await capture.dispose();
      hid.dispose();
    },
  );

  testWidgets(
    'holding the quick mic opens multilingual settings without quick-starting',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        dictationConsentPreferenceKey: true,
      });
      final hid = RecordingHidService();
      final companion = RecordingCompanionService()
        ..host.value = _dictationHost();
      final capture = _FakeCapture();
      var configuredLanguage = DictationLanguage.chinese;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [localDictationRouteObserver],
          home: Scaffold(
            body: LocalDictationEntryButton(
              hid: hid,
              companion: companion,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, language) async {
                configuredLanguage = language;
                return _FakeRecognizer(text: 'hello');
              },
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byKey(const ValueKey('local-quick-output')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('local-dictation-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dictation-output-mode')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dictation-language')), findsNothing);
      expect(
        capture.startCount,
        0,
        reason: 'hold opens options, not quick start',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('start-dictation')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<DictationOutputMode>>(
              find.byKey(const ValueKey('dictation-output-mode')),
            )
            .onChanged,
        isNotNull,
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-output-mode')),
      );
      final desktopOption = find.byKey(
        const ValueKey('dictation-output-desktopMultilingual'),
      );
      expect(desktopOption, findsOneWidget);
      await _tapVisible(tester, desktopOption);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dictation-language')), findsOneWidget);
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-language')),
      );
      final englishOption = find.text('English').hitTestable();
      expect(englishOption, findsOneWidget);
      await tester.tap(englishOption);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(configuredLanguage, DictationLanguage.english);
      expect(capture.startCount, 1);
      expect(hid.textBatches, isEmpty, reason: 'desktop mode uses no HID');

      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      await capture.dispose();
      hid.dispose();
      companion.dispose();
    },
  );

  testWidgets(
    'live panel collapses without blocking shortcuts and shows PCM level',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hid = _readyHid();
      final capture = _FakeCapture();
      final allowWakeLockRelease = Completer<void>();
      var wakeLockReleaseCount = 0;
      var overlayVisible = true;
      var shortcutTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => Stack(
                children: [
                  Center(
                    child: TextButton(
                      key: const ValueKey('underlying-shortcut'),
                      onPressed: () async {
                        shortcutTaps++;
                        await hid.sendPress(
                          const HidAction(
                            type: ActionType.keyboard,
                            keyCode: 'KEY_A',
                          ),
                        );
                      },
                      child: const Text('Shortcut'),
                    ),
                  ),
                  if (overlayVisible)
                    Positioned.fill(
                      child: LocalDictationPanel(
                        hid: hid,
                        modelManager: _FakeModelManager(),
                        capture: capture,
                        recognizerFactory: (_, _) async =>
                            _FakeRecognizer(text: 'hello'),
                        enableWakeLock: () async {},
                        disableWakeLock: () {
                          wakeLockReleaseCount++;
                          return allowWakeLockRelease.future;
                        },
                        autoCollapseWhileListening: true,
                        onDismiss: () => setState(() => overlayVisible = false),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('dictation-entry-barrier')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('dictation-output-mode')), findsNothing);
      expect(capture.startCount, 1);

      final chipSemantics = find.byKey(
        const ValueKey('dictation-live-chip-semantics'),
      );
      expect(
        tester.widget<Semantics>(chipSemantics).properties.value,
        contains('0 percent'),
      );
      await tester.runAsync(() async {
        for (var chunk = 0; chunk < 4; chunk++) {
          capture.audio.add(
            List<int>.generate(6400, (index) => index.isEven ? 0x10 : 0x27),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(
        tester.widget<Semantics>(chipSemantics).properties.value,
        isNot(contains('0 percent')),
      );

      await tester.tap(find.byKey(const ValueKey('underlying-shortcut')));
      await tester.pumpAndSettle();
      expect(shortcutTaps, 1);
      expect(hid.pressedActions, hasLength(1));
      expect(capture.startCount, 1, reason: 'shortcut use keeps capture live');

      capture.audio.add(List<int>.filled(32000, 0));
      for (var frame = 0; frame < 30 && hid.textBatches.isEmpty; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(hid.textBatches, hasLength(1));
      expect(
        hid.textBatches.single.strokes,
        UsAsciiHidTextEncoder.encode('hello'),
      );
      expect(capture.stopCount, 0);

      await tester.tap(find.byKey(const ValueKey('stop-dictation-compact')));
      await tester.pump();
      expect(capture.stopCount, 1);
      for (var frame = 0; frame < 30 && wakeLockReleaseCount == 0; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(wakeLockReleaseCount, 1);
      expect(
        tester
            .widget<InkWell>(
              find.byKey(const ValueKey('stop-dictation-compact')),
            )
            .onTap,
        isNull,
        reason: 'a second tap is disabled while Stop cleanup is pending',
      );
      await tester.tap(
        find.byKey(const ValueKey('stop-dictation-compact')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(capture.stopCount, 1);
      expect(wakeLockReleaseCount, 1);
      allowWakeLockRelease.complete();
      await tester.pumpAndSettle();
      expect(overlayVisible, isFalse);
      expect(
        find.byKey(const ValueKey('stop-dictation-compact')),
        findsNothing,
      );
      hid.dispose();
    },
  );

  testWidgets(
    'recognizer reconfiguration locks Start until output and language changes finish',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final hid = _readyHid();
      final companion = RecordingCompanionService()
        ..host.value = _dictationHost();
      final capture = _FakeCapture();
      final languages = <DictationLanguage>[];
      final recognizers = <_DelayedDisposeRecognizer>[];
      var releasedWakeLocks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              companion: companion,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, language) async {
                languages.add(language);
                final recognizer = _DelayedDisposeRecognizer();
                recognizers.add(recognizer);
                return recognizer;
              },
              enableWakeLock: () async {},
              disableWakeLock: () async {
                releasedWakeLocks++;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      await tester.pumpAndSettle();
      for (var frame = 0; frame < 30 && releasedWakeLocks < 1; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(languages.single, DictationLanguage.english);
      expect(capture.stopCount, 1, reason: 'Stop releases microphone capture');
      expect(
        releasedWakeLocks,
        1,
        reason: 'Stop finishes wake-lock cleanup before configuration',
      );
      expect(
        tester
            .widget<DropdownButtonFormField<DictationOutputMode>>(
              find.byKey(const ValueKey('dictation-output-mode')),
            )
            .onChanged,
        isNotNull,
        reason: 'output selection is enabled after Stop cleanup completes',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('start-dictation')))
            .onPressed,
        isNotNull,
        reason: 'Start is enabled after Stop cleanup completes',
      );

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-output-mode')),
      );
      await tester.tap(find.text('LumiaKey Desktop · multilingual').last);
      await tester.pump();
      await recognizers.first.disposeStarted.future;
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('start-dictation')))
            .onPressed,
        isNull,
      );
      expect(
        capture.startCount,
        1,
        reason: 'configuration must block another capture',
      );
      expect(hid.textBatches, isEmpty);
      recognizers.first.allowDispose.complete();
      await tester.pumpAndSettle();
      expect(find.text('LumiaKey Desktop · multilingual'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      await tester.pumpAndSettle();
      for (var frame = 0; frame < 30 && releasedWakeLocks < 2; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(languages.last, DictationLanguage.chinese);
      expect(capture.stopCount, 2, reason: 'second Stop releases capture');
      expect(releasedWakeLocks, 2, reason: 'second Stop releases wake lock');
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-language')),
      );
      await tester.tap(find.text('English').last);
      await tester.pump();
      await recognizers.last.disposeStarted.future;
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('start-dictation')))
            .onPressed,
        isNull,
      );
      expect(capture.startCount, 2);
      recognizers.last.allowDispose.complete();
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('dictation-output-mode')),
      );
      await tester.tap(find.text('Bluetooth English').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(languages.last, DictationLanguage.english);
      expect(capture.startCount, 3);
      recognizers.last.allowDispose.complete();
      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      await tester.pumpAndSettle();
      for (
        var frame = 0;
        frame < 30 && (capture.stopCount < 3 || releasedWakeLocks < 3);
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(capture.stopCount, 3);
      expect(releasedWakeLocks, 3);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      hid.dispose();
      companion.dispose();
    },
  );

  testWidgets('start holds wake lock and disconnect/background stop capture', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final manager = _FakeModelManager();
    final hid = _readyHid();
    var wakeCount = 0;
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
            modelManager: manager,
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {
              wakeCount++;
            },
            disableWakeLock: () async {
              releaseCount++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    expect(capture.startCount, 1);
    expect(wakeCount, 1);
    expect(find.byKey(const ValueKey('stop-dictation')), findsOneWidget);

    hid.selectedHost.value = null;
    hid.status.value = HidConnectionStatus.disconnected;
    for (var frame = 0; frame < 20 && releaseCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    await tester.pumpAndSettle();
    expect(capture.stopCount, 1);
    expect(releaseCount, greaterThanOrEqualTo(1));
    expect(find.textContaining('Bluetooth host disconnected'), findsOneWidget);

    hid.selectedHost.value = const HidHost(
      id: 'test-host',
      name: 'Desktop',
      address: '00:11:22:33:44:55',
    );
    hid.status.value = HidConnectionStatus.connected;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    expect(capture.startCount, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    for (var frame = 0; frame < 20 && releaseCount < 2; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    await tester.pumpAndSettle();
    expect(capture.stopCount, 2);
    expect(releaseCount, greaterThanOrEqualTo(2));
    hid.dispose();
  });

  testWidgets('dictation session stays pinned to its Bluetooth address', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {},
            disableWakeLock: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();

    hid.selectedHost.value = const HidHost(
      id: 'test-host',
      name: 'Renamed computer',
      address: '00:11:22:33:44:55',
    );
    await tester.pumpAndSettle();
    expect(
      capture.stopCount,
      0,
      reason: 'manifest refresh keeps the same selected host active',
    );
    hid.selectedHost.value = const HidHost(
      id: 'other-host',
      name: 'Other computer',
      address: '11:22:33:44:55:66',
    );
    for (var frame = 0; frame < 20 && capture.stopCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(capture.stopCount, 1);
    expect(hid.textBatches, isEmpty);
    hid.dispose();
  });

  testWidgets('wake-lock failure stops the microphone after capture starts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid();
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async => throw StateError('wake lock failed'),
            disableWakeLock: () async {
              releaseCount++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    for (var frame = 0; frame < 20 && capture.stopCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    await tester.pumpAndSettle();
    expect(capture.startCount, 1);
    expect(capture.stopCount, 1);
    expect(releaseCount, 1);
    expect(find.textContaining('wake lock failed'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    hid.dispose();
  });

  testWidgets('unexpected capture failure releases the wake lock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid();
    var releaseCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {},
            disableWakeLock: () async {
              releaseCount++;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    capture.audio.addError(StateError('capture interrupted'));
    for (var frame = 0; frame < 20 && releaseCount == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(capture.stopCount, 1);
    expect(releaseCount, 1);
    expect(find.textContaining('capture interrupted'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    hid.dispose();
  });

  testWidgets('Stop types each finalized ASCII phrase once over Bluetooth', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {},
            disableWakeLock: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();

    capture.audio.add(
      List<int>.generate(3200, (index) => index.isEven ? 16 : 39),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const ValueKey('stop-dictation')));
    for (var frame = 0; frame < 20 && hid.textBatches.isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(hid.textBatches, hasLength(1));
    expect(hid.textBatches.single.expectedAddress, '00:11:22:33:44:55');
    expect(
      hid.textBatches.single.strokes,
      hasLength('recognized phrase'.length),
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    hid.dispose();
  });

  testWidgets('Bluetooth report failure is visible and never retried', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final capture = _FakeCapture();
    final hid = _readyHid()
      ..textBatchError = StateError('Bluetooth rejected a keyboard report');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalDictationPanel(
            hid: hid,
            modelManager: _FakeModelManager(),
            capture: capture,
            recognizerFactory: (_, _) async => _FakeRecognizer(),
            enableWakeLock: () async {},
            disableWakeLock: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-dictation')));
    await tester.pumpAndSettle();
    capture.audio.add(
      List<int>.generate(3200, (index) => index.isEven ? 16 : 39),
    );
    await tester.pump(const Duration(milliseconds: 20));
    await tester.tap(find.byKey(const ValueKey('stop-dictation')));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      if (find.byKey(const ValueKey('dictation-error')).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(hid.textBatches, hasLength(1));
    expect(
      find.textContaining('Bluetooth rejected a keyboard report'),
      findsOneWidget,
    );
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    hid.dispose();
  });

  testWidgets(
    'disconnect cancels text output while Stop flushes its final phrase',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture();
      final hid = _readyHid();
      final batchStarted = Completer<void>();
      final batchCancelled = Completer<void>();
      final batchRelease = Completer<void>();
      hid.onTextBatch = () {
        if (!batchStarted.isCompleted) batchStarted.complete();
        return batchRelease.future;
      };
      hid.onCancelTextBatch = (_) async {
        if (!batchCancelled.isCompleted) batchCancelled.complete();
        if (!batchRelease.isCompleted) {
          batchRelease.completeError(
            const HidTextOutputException('Bluetooth dictation was cancelled.'),
          );
        }
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      capture.audio.add(
        List<int>.generate(3200, (index) => index.isEven ? 16 : 39),
      );
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      for (var frame = 0; frame < 20 && !batchStarted.isCompleted; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(batchStarted.isCompleted, isTrue);

      hid.selectedHost.value = null;
      hid.status.value = HidConnectionStatus.disconnected;
      for (var frame = 0; frame < 20 && !batchCancelled.isCompleted; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(batchCancelled.isCompleted, isTrue);
      expect(hid.cancelledTextBatches, hasLength(1));
      expect(capture.stopCount, 1);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      hid.dispose();
    },
  );

  testWidgets(
    'Bluetooth navigation interruption keeps mic live for a later phrase',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture();
      final hid = _readyHid();
      var attempts = 0;
      hid.onTextBatch = () async {
        attempts++;
        if (attempts == 1) {
          throw PlatformException(
            code: 'NAVIGATION_INTERRUPTED',
            message: 'manual navigation interrupted this phrase',
          );
        }
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(text: 'hello'),
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();

      Future<void> finalizePhrase(int batchCount) async {
        capture.audio.add(
          List<int>.generate(6400, (index) => index.isEven ? 0x10 : 0x27),
        );
        await tester.pump(const Duration(milliseconds: 20));
        capture.audio.add(List<int>.filled(32000, 0));
        for (var frame = 0; frame < 60 && attempts < batchCount; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 1)),
          );
        }
      }

      await finalizePhrase(1);
      expect(attempts, 1);
      expect(capture.startCount, 1);
      expect(capture.stopCount, 0);
      expect(
        find.textContaining('This phrase was skipped; dictation continues'),
        findsOneWidget,
      );

      await finalizePhrase(2);
      expect(attempts, 2);
      expect(hid.textBatches, hasLength(2));
      expect(
        hid.textBatches.last.strokes,
        UsAsciiHidTextEncoder.encode('hello'),
      );
      expect(capture.startCount, 1);
      expect(capture.stopCount, 0);
      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      await capture.dispose();
      hid.dispose();
    },
  );

  testWidgets(
    'Bluetooth report failure cancels capture and does not request another phrase',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture();
      final hid = _readyHid();
      var wakeLockReleases = 0;
      var attempts = 0;
      hid.onTextBatch = () async {
        attempts++;
        throw PlatformException(
          code: 'REPORT_FAILED',
          message: 'native report rejected',
        );
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              modelManager: _FakeModelManager(),
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(text: 'hello'),
              enableWakeLock: () async {},
              disableWakeLock: () async => wakeLockReleases++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      capture.audio.add(
        List<int>.generate(6400, (index) => index.isEven ? 0x10 : 0x27),
      );
      await tester.pump(const Duration(milliseconds: 20));
      capture.audio.add(List<int>.filled(32000, 0));
      for (
        var frame = 0;
        frame < 60 && (capture.stopCount == 0 || wakeLockReleases == 0);
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1)),
        );
      }
      expect(attempts, 1);
      expect(hid.textBatches, hasLength(1));
      expect(capture.startCount, 1);
      expect(capture.stopCount, 1);
      expect(wakeLockReleases, 1);
      expect(
        find.textContaining(
          'Bluetooth text delivery failed; dictation stopped',
        ),
        findsOneWidget,
      );

      capture.audio.add(
        List<int>.generate(6400, (index) => index.isEven ? 0x10 : 0x27),
      );
      capture.audio.add(List<int>.filled(32000, 0));
      await tester.pump(const Duration(milliseconds: 100));
      expect(attempts, 1, reason: 'failed phrase is never replayed');
      expect(hid.textBatches, hasLength(1));
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      await capture.dispose();
      hid.dispose();
    },
  );

  testWidgets(
    'quick entry auto-starts a warm model and never downloads implicitly',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final warmCapture = _FakeCapture();
      final warmManager = _FakeModelManager();
      final warmHid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: warmHid,
              modelManager: warmManager,
              capture: warmCapture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
              autoStartWhenReady: true,
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(warmCapture.startCount, 1);
      expect(warmManager.prepareCount, 0);
      expect(find.byKey(const ValueKey('stop-dictation')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('stop-dictation')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      warmHid.dispose();

      final missingCapture = _FakeCapture();
      final missingManager = _FakeModelManager(ready: false);
      final missingHid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: missingHid,
              modelManager: missingManager,
              capture: missingCapture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
              autoStartWhenReady: true,
              enableWakeLock: () async {},
              disableWakeLock: () async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(missingCapture.startCount, 0);
      expect(missingManager.prepareCount, 0);
      expect(
        find.byKey(const ValueKey('download-dictation-model')),
        findsOneWidget,
      );
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();
      missingHid.dispose();
    },
  );

  testWidgets(
    'model download and deletion are explicit and permission failure blocks capture',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final capture = _FakeCapture()..permitted = false;
      final manager = _FakeModelManager(ready: false);
      final hid = _readyHid();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocalDictationPanel(
              hid: hid,
              modelManager: manager,
              capture: capture,
              recognizerFactory: (_, _) async => _FakeRecognizer(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('download-dictation-model')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('download-dictation-model')));
      await tester.pumpAndSettle();
      expect(manager.prepareCount, 1);
      expect(find.textContaining('Installed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('start-dictation')));
      await tester.pumpAndSettle();
      expect(capture.startCount, 0);
      expect(
        find.textContaining('Microphone permission is needed'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('dictation-error')), findsOneWidget);

      capture.permitted = true;
      await tester.tap(find.byKey(const ValueKey('delete-dictation-model')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(manager.deleteCount, 1);
      expect(find.textContaining('Not installed'), findsOneWidget);
      hid.dispose();
    },
  );
}

RecordingHidService _readyHid() {
  final service = RecordingHidService();
  service.selectedHost.value = const HidHost(
    id: 'test-host',
    name: 'Computer',
    address: '00:11:22:33:44:55',
  );
  service.status.value = HidConnectionStatus.connected;
  return service;
}

CompanionHost _dictationHost() => const CompanionHost(
  name: 'PC',
  platform: 'windows',
  address: '192.168.1.20',
  port: 45833,
  token: 'test-token',
  protocolVersion: 2,
  capabilities: {'manifest', 'local-dictation-v1'},
);

class _FakeModelManager extends ModelManager {
  _FakeModelManager({this.ready = true});
  bool ready;

  @override
  LocalAsrModelDescriptor descriptor(
    LocalAsrModel model,
  ) => LocalAsrModelDescriptor(
    model: model,
    directory: model.name,
    repository: 'test/models',
    revision: 'test-revision',
    primaryModelFile: 'model.onnx',
    files: const [
      LocalAsrFile(
        name: 'model.onnx',
        sizeBytes: 16,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
    ],
  );

  int prepareCount = 0;
  int deleteCount = 0;

  @override
  Future<bool> areModelsAvailable({
    LocalAsrModel model = LocalAsrModel.senseVoice,
  }) async => ready;

  @override
  Future<LocalAsrModelFiles> installedModel(LocalAsrModel model) async =>
      LocalAsrModelFiles(
        model: model,
        modelPath: 'model.onnx',
        tokensPath: 'tokens.txt',
      );

  @override
  Future<LocalAsrModelFiles> prepareModel(
    LocalAsrModel model, {
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    prepareCount++;
    ready = true;
    return installedModel(model);
  }

  @override
  Future<LocalAsrModelFiles> importModel(
    LocalAsrModel model,
    Directory source,
  ) => installedModel(model);

  @override
  Future<void> deleteModel(LocalAsrModel model) async {
    deleteCount++;
    ready = false;
  }
}

class _FakeCapture implements DictationCapture {
  StreamController<List<int>> audio = StreamController<List<int>>.broadcast();
  int startCount = 0;
  int stopCount = 0;
  bool permitted = true;

  @override
  Future<bool> hasPermission() async => permitted;

  @override
  Future<Stream<List<int>>> start() async {
    if (startCount > 0) {
      audio = StreamController<List<int>>.broadcast();
    }
    startCount++;
    return audio.stream;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    await audio.close();
  }
}

class _FakeRecognizer implements DictationRecognizer {
  _FakeRecognizer({this.text = 'recognized phrase'});

  final String text;

  @override
  Future<String> transcribe(
    Float32List samples, {
    DictationLanguage? language,
  }) async => text;

  @override
  Future<void> dispose({bool flush = true}) async {}
}

class _PartialRejectingCompanion extends RecordingCompanionService {
  int attempts = 0;

  @override
  Future<void> sendDictation({
    required String sessionId,
    required int sequence,
    required String text,
  }) async {
    attempts++;
    await super.sendDictation(
      sessionId: sessionId,
      sequence: sequence,
      text: text,
    );
    throw StateError('PC rejected text after partial insertion');
  }
}

class _BusyOnceCompanion extends RecordingCompanionService {
  int attempts = 0;

  @override
  Future<void> sendDictation({
    required String sessionId,
    required int sequence,
    required String text,
  }) async {
    attempts++;
    if (attempts == 1) {
      throw const CompanionInputBusyException(
        'A manual keyboard shortcut is active.',
      );
    }
    await super.sendDictation(
      sessionId: sessionId,
      sequence: sequence,
      text: text,
    );
  }
}

class _DelayedDisposeRecognizer implements DictationRecognizer {
  final disposeStarted = Completer<void>();
  final allowDispose = Completer<void>();

  @override
  Future<String> transcribe(
    Float32List samples, {
    DictationLanguage? language,
  }) async => 'recognized phrase';

  @override
  Future<void> dispose({bool flush = true}) {
    if (!disposeStarted.isCompleted) disposeStarted.complete();
    return allowDispose.future;
  }
}
