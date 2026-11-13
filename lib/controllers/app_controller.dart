import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import '../data/config_repository.dart';
import '../data/account_backup_codec.dart';
import '../data/private_image_store.dart';
import '../data/profile_template_repository.dart';
import '../data/public_shortcut_catalog.dart';
import '../data/shortcut_usage_repository.dart';
import '../models/config.dart';
import '../models/computer_setup.dart';
import '../models/control_surface_status.dart';
import '../services/hid_service.dart';
import '../services/ios_companion_hid_service.dart';
import '../services/companion_service.dart';
import '../services/orientation_service.dart';
import '../services/power_brightness_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.templates,
    required this.hid,
    required this.companion,
    required this.orientationService,
    required this.imageStore,
    required this.powerBrightnessService,
    required this.shortcutUsage,
    this.platformOverride,
  }) {
    hid.activeHost.addListener(_handleActiveHostChanged);
    hid.connectionStatus.addListener(_handleActiveHostChanged);
    hid.pairedHosts.addListener(notifyListeners);
    companion.activeHost.addListener(_handleCompanionHostChanged);
    companion.manifest.addListener(_handleCompanionManifestChanged);
    companion.syncStatus.addListener(_handleCompanionManifestChanged);
    companion.errorMessage.addListener(_handleCompanionManifestChanged);
    desktopComputerChoices?.addListener(notifyListeners);
    powerBrightnessService.isPluggedIn.addListener(_handlePowerChanged);
  }

  final ConfigRepository repository;
  final ProfileTemplateRepository templates;
  final HidService hid;
  final CompanionService companion;
  final OrientationService orientationService;
  final PrivateImageStore imageStore;
  final PowerBrightnessService powerBrightnessService;
  final ShortcutUsageRepository shortcutUsage;
  final TargetPlatform? platformOverride;

  AppConfig? _config;
  String? _acceptedCompanionSession;
  String? _acceptedCompanionComputerId;
  Future<void> _computerSetupSaveQueue = Future<void>.value();
  bool _isLoading = true;
  Object? _error;
  bool? _lastLandscape;
  int _inputEpoch = 0;
  final Set<int> _pressedPositions = {};
  final Map<int, HidAction> _pressedButtonActions = {};
  HidAction? _pressedWheelCenterAction;
  double _touchpadScrollAccumulator = 0;
  Future<void> _darkTransition = Future.value();
  ButtonConfig? _buttonClipboard;
  int _profileIdSequence = 0;
  bool _darkModeActive = false;
  late final IosCompanionHidService _desktopShortcutHid =
      hid is IosCompanionHidService
      ? hid as IosCompanionHidService
      : IosCompanionHidService(companion);
  int _computerSwitchEpoch = 0;
  String? _computerSwitchPendingId;
  String? _computerSwitchError;
  String? _pinnedDesktopChoiceId;

  static const _darkPhoneBrightness = 0.1;
  static const _displayBrightnessDownSteps = 20;
  static const _displayBrightnessUpSteps = 20;
  static const _keyboardBrightnessSteps = 16;

  bool get isLoading => _isLoading;
  Object? get error => _error;
  AppConfig get config => _config!;
  ProfileConfig get activeProfile => config.activeProfile;
  Set<int> get pressedPositions => Set.unmodifiable(_pressedPositions);
  int get inputEpoch => _inputEpoch;
  bool get hasButtonClipboard => _buttonClipboard != null;
  bool get canAddProfile => config.profiles.length < freeProfileLimit;
  bool get isDarkModeActive => _darkModeActive;
  DesktopManifest? get desktopManifest => companion.manifest.value;
  ValueListenable<List<CompanionComputerChoice>>? get desktopComputerChoices =>
      companion is SwitchableCompanionConnection
      ? (companion as SwitchableCompanionConnection).computerChoices
      : null;
  String? get selectedDesktopComputerChoiceId =>
      companion is SwitchableCompanionConnection
      ? (companion as SwitchableCompanionConnection).selectedComputerChoiceId
      : null;
  String? get computerSwitchPendingId => _computerSwitchPendingId;
  String? get computerSwitchError => _computerSwitchError;
  bool get hasPinnedDesktopComputer => _pinnedDesktopChoiceId != null;

  List<({String id, String name})> get switchableComputers {
    final choices = <({String id, String name})>[];
    for (final host
        in desktopComputerChoices?.value ?? const <CompanionComputerChoice>[]) {
      choices.add((id: 'desktop:${host.id}', name: host.name));
    }
    choices.sort((a, b) {
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return choices;
  }

  String? get selectedSwitchableComputerId {
    final host = companion.activeHost.value;
    if (host != null && _isAcceptedCompanionHost(host)) {
      final selectedId = selectedDesktopComputerChoiceId;
      return 'desktop:${selectedId ?? _desktopComputerSetupId(host).substring('desktop:'.length)}';
    }
    return null;
  }

  Future<bool> switchComputer(String choiceId) async {
    if (_computerSwitchPendingId != null) return false;
    ({String id, String name})? target;
    for (final choice in switchableComputers) {
      if (choice.id == choiceId) target = choice;
    }
    if (target == null) return false;
    final epoch = ++_computerSwitchEpoch;
    _computerSwitchPendingId = choiceId;
    _computerSwitchError = null;
    notifyListeners();
    try {
      await prepareForContextChange();
      if (epoch != _computerSwitchEpoch) return false;
      _pinnedDesktopChoiceId = choiceId.substring('desktop:'.length);
      if (_isAndroid &&
          (hid.activeHost.value != null ||
              hid.connectionStatus.value == HidConnectionStatus.connected ||
              hid.connectionStatus.value == HidConnectionStatus.connecting)) {
        await hid.disconnectHost();
      }
      if (epoch != _computerSwitchEpoch) return false;
      final switchable = companion as SwitchableCompanionConnection;
      await switchable.selectComputer(choiceId.substring('desktop:'.length));
      return epoch == _computerSwitchEpoch;
    } catch (error) {
      if (epoch == _computerSwitchEpoch) {
        _computerSwitchError = error.toString().replaceFirst('Exception: ', '');
      }
      return false;
    } finally {
      if (epoch == _computerSwitchEpoch) {
        _computerSwitchPendingId = null;
        notifyListeners();
      }
    }
  }

  bool get _isAndroid =>
      (platformOverride ?? defaultTargetPlatform) == TargetPlatform.android;
  bool get _isIos =>
      (platformOverride ?? defaultTargetPlatform) == TargetPlatform.iOS;
  bool get hasDesktopComputerChoices => switchableComputers.isNotEmpty;

  /// Called only when the user explicitly chooses an Android Bluetooth host.
  /// This clears a prior Desktop KVM pin so HID input can resume directly.
  Future<void> prepareForBluetoothHostSelection() async {
    ++_computerSwitchEpoch;
    _computerSwitchPendingId = null;
    _pinnedDesktopChoiceId = null;
    notifyListeners();
    await prepareForContextChange();
    if (companion is SwitchableCompanionConnection) {
      await (companion as SwitchableCompanionConnection)
          .suspendComputerSelection();
    }
    notifyListeners();
  }

  ComputerMode get computerMode =>
      activeComputer?.mode ?? ComputerMode.disconnected;

  /// A recently authenticated Desktop session stays selected during manifest
  /// refreshes and action errors, provided the same host session remains.
  ComputerTarget? get activeComputer {
    final host = companion.activeHost.value;
    if (_pinnedDesktopChoiceId != null &&
        (host == null ||
            !_isAcceptedCompanionHost(host) ||
            selectedDesktopComputerChoiceId != _pinnedDesktopChoiceId)) {
      return null;
    }
    if (host != null) {
      if (!_isAcceptedCompanionHost(host)) return null;
      final operatingSystem = _computerOperatingSystemFromPlatform(
        host.platform,
      );
      return ComputerTarget(
        id: _desktopComputerSetupId(host),
        name: host.name,
        mode: ComputerMode.advanced,
        isApple: operatingSystem == null
            ? host.isApple
            : operatingSystem == ComputerOperatingSystem.macos,
        operatingSystem: operatingSystem,
      );
    }
    if (_isIos ||
        !_isAndroid ||
        hid.connectionStatus.value != HidConnectionStatus.connected) {
      return null;
    }
    final bluetoothHost = hid.activeHost.value;
    if (bluetoothHost == null) return null;
    final targetId = _bluetoothComputerSetupId(bluetoothHost);
    final operatingSystem = _standaloneOperatingSystem(bluetoothHost, targetId);
    return ComputerTarget(
      id: targetId,
      name: bluetoothHost.name,
      mode: ComputerMode.standalone,
      isApple:
          _standaloneShortcutPlatform(bluetoothHost) == ShortcutPlatform.apple,
      operatingSystem: operatingSystem,
    );
  }

  ComputerSetup? get activeComputerSetup {
    final target = activeComputer;
    return target == null ? null : config.computerSetups[target.id];
  }

  List<ComputerApplication> get availableComputerApplications {
    final target = activeComputer;
    if (target == null) return const [];
    final selected = activeComputerSetup?.applicationIds.toSet() ?? const {};
    return computerApplicationsOnActiveComputer
        .where(
          (application) =>
              selected.contains(application.id) &&
              isComputerApplicationSupportedOn(
                application,
                target.operatingSystem,
              ),
        )
        .toList(growable: false);
  }

  /// App choices used when first setting up or changing this computer's
  /// selected software. The top row uses [availableComputerApplications].
  List<ComputerApplication> get computerApplicationsOnActiveComputer {
    final target = activeComputer;
    if (target == null) return const [];
    if (target.mode == ComputerMode.standalone) {
      return computerApplicationsForOperatingSystem(target.operatingSystem);
    }
    final manifest = desktopManifest;
    if (target.mode != ComputerMode.advanced ||
        !isDesktopSynced ||
        manifest?.settings.enableAppsSync != true) {
      return const [];
    }
    return manifest!.applications
        .where((application) => application.detected)
        .map(
          (application) =>
              computerApplicationById(application.id) ??
              ComputerApplication(
                id: application.id,
                name: application.name,
                category: ComputerAppCategory.other,
              ),
        )
        .where(
          (application) => isComputerApplicationSupportedOn(
            application,
            target.operatingSystem,
          ),
        )
        .toList(growable: false);
  }

  bool get isStandaloneSetupComplete {
    final target = activeComputer;
    if (target?.mode != ComputerMode.standalone) return false;
    final setup = activeComputerSetup;
    // Saving the selected applications completes setup. Shortcut bindings can
    // be added or edited later, so an incomplete set must not reopen onboarding.
    return setup?.setupComplete ?? false;
  }

  bool get isActiveComputerSetupComplete {
    final target = activeComputer;
    if (target == null || activeComputerSetup == null) return false;
    if (target.mode == ComputerMode.standalone) {
      return isStandaloneSetupComplete;
    }
    return target.mode == ComputerMode.advanced &&
        activeComputerSetup!.setupComplete;
  }

  Future<void> saveComputerSetup(ComputerTarget target, ComputerSetup setup) =>
      _queueComputerSetupSave(
        () => _saveComputerSetupForCurrentTarget(target, setup),
      );

  Future<void> saveComputerOperatingSystem(
    ComputerTarget target,
    ComputerOperatingSystem operatingSystem,
  ) => _queueComputerSetupSave(() async {
    _requireCurrentStandaloneTarget(target);
    final existing = config.computerSetups[target.id];
    await _saveComputerSetupRecord(
      target.id,
      ComputerSetup(
        applicationIds: existing?.applicationIds ?? const [],
        bindings: existing?.bindings ?? const {},
        operatingSystem: operatingSystem,
        setupComplete: existing?.setupComplete ?? false,
      ),
    );
  });

  Future<void> _queueComputerSetupSave(Future<void> Function() save) async {
    final previousSave = _computerSetupSaveQueue;
    final completer = Completer<void>();
    _computerSetupSaveQueue = completer.future;
    try {
      try {
        await previousSave;
      } catch (_) {
        // A failed previous save must not block the next connection's setup.
      }
      await save();
      completer.complete();
    } catch (error, stackTrace) {
      completer.complete();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> _saveComputerSetupForCurrentTarget(
    ComputerTarget target,
    ComputerSetup setup,
  ) async {
    final current = _requireCurrentComputerTarget(target);
    if (target.mode == ComputerMode.advanced && !isDesktopSynced) {
      throw StateError('Wait for Desktop to finish syncing before saving.');
    }
    if (target.mode == ComputerMode.advanced &&
        setup.applicationIds.isNotEmpty &&
        desktopManifest?.settings.enableAppsSync != true) {
      throw StateError('Turn on Apps Sync in Desktop before choosing apps.');
    }
    if (target.mode == ComputerMode.advanced && setup.bindings.isNotEmpty) {
      throw const FormatException(
        'Desktop mode uses shortcuts saved in the Desktop companion.',
      );
    }
    final previous = config.computerSetups[target.id];
    final chosenOperatingSystem = target.mode == ComputerMode.advanced
        ? current.operatingSystem
        : setup.operatingSystem ?? previous?.operatingSystem;
    final applicationOperatingSystem =
        chosenOperatingSystem ?? current.operatingSystem;
    final unsupportedPreviousApps = previous?.applicationIds
        .where((appId) {
          final application = computerApplicationById(appId);
          return application != null &&
              !isComputerApplicationSupportedOn(
                application,
                applicationOperatingSystem,
              );
        })
        .toList(growable: false);
    final preservedBindings = <String, Map<String, String>>{...setup.bindings};
    for (final appId in unsupportedPreviousApps ?? const <String>[]) {
      final bindings = previous?.bindings[appId];
      if (bindings != null) preservedBindings[appId] = bindings;
    }
    for (final appId in setup.applicationIds) {
      final application = _computerApplicationFor(target, appId);
      if (application != null &&
          !isComputerApplicationSupportedOn(
            application,
            applicationOperatingSystem,
          ) &&
          !(previous?.applicationIds.contains(appId) ?? false)) {
        throw FormatException(
          '${application.name} is unavailable on this operating system.',
        );
      }
    }
    final setupToSave = ComputerSetup(
      applicationIds: [
        ...setup.applicationIds,
        ...?unsupportedPreviousApps?.where(
          (appId) => !setup.applicationIds.contains(appId),
        ),
      ],
      bindings: preservedBindings,
      operatingSystem: chosenOperatingSystem,
      setupComplete: setup.setupComplete,
    );
    final launchBindings = <String, String>{};
    for (final appId in setupToSave.applicationIds) {
      final application = _computerApplicationFor(target, appId);
      if (application == null) {
        throw FormatException('Unknown computer app: $appId');
      }
      if (!isComputerApplicationSupportedOn(
        application,
        setupToSave.operatingSystem,
      )) {
        continue;
      }
      if (target.mode == ComputerMode.advanced &&
          desktopManifest!.applications.every(
            (installed) => installed.id != appId || !installed.detected,
          )) {
        throw FormatException(
          '${application.name} is not detected on this computer.',
        );
      }
      if (target.mode == ComputerMode.standalone) {
        for (final shortcut in computerShortcutsFor(application.category)) {
          final chord = setup.bindingFor(appId, shortcut.id);
          if (chord != null &&
              chord.trim().isNotEmpty &&
              parseComputerShortcut(chord) == null) {
            throw FormatException(
              '${application.name}: ${shortcut.label} has an unsupported shortcut.',
            );
          }
          if (shortcut.id == 'launch' &&
              chord != null &&
              chord.trim().isNotEmpty) {
            final identity = _computerChordIdentity(chord);
            final previousApplication = launchBindings[identity];
            if (previousApplication != null) {
              throw FormatException(
                'Choose a different launch shortcut for ${application.name}.',
              );
            }
            launchBindings[identity] = application.name;
          }
        }
      }
      if (application.category == ComputerAppCategory.vibeCoding &&
          target.mode == ComputerMode.standalone &&
          _sameComputerChord(
            setup.bindingFor(appId, 'voiceMode'),
            setup.bindingFor(appId, 'voiceInput'),
          )) {
        throw const FormatException(
          'Choose different shortcuts for voice mode and voice input.',
        );
      }
    }
    await _saveComputerSetupRecord(target.id, setupToSave);
  }

  Future<void> _saveComputerSetupRecord(
    String targetId,
    ComputerSetup setup,
  ) async {
    var base = config;
    var nextConfig = _computerSetupConfig(base, targetId, setup);
    await repository.save(nextConfig);
    while (!identical(_config, base)) {
      base = config;
      nextConfig = _computerSetupConfig(base, targetId, setup);
      await repository.save(nextConfig);
    }
    _config = nextConfig;
    notifyListeners();
  }

  ComputerTarget _requireCurrentStandaloneTarget(ComputerTarget target) {
    if (target.mode != ComputerMode.standalone) {
      throw const FormatException(
        'Choose the computer OS in Bluetooth-only setup.',
      );
    }
    return _requireCurrentComputerTarget(target);
  }

  ComputerTarget _requireCurrentComputerTarget(ComputerTarget target) {
    final current = activeComputer;
    if (current?.mode != target.mode ||
        current?.id != target.id ||
        (target.mode != ComputerMode.standalone &&
            target.mode != ComputerMode.advanced)) {
      throw StateError('Reconnect to the same computer to save its setup.');
    }
    return current!;
  }

  static AppConfig _computerSetupConfig(
    AppConfig base,
    String targetId,
    ComputerSetup setup,
  ) {
    final setups = Map<String, ComputerSetup>.of(base.computerSetups)
      ..[targetId] = setup;
    return base.copyWith(
      computerSetups: Map<String, ComputerSetup>.unmodifiable(setups),
    );
  }

  /// Send a configured global app-launch chord from the Android wizard.
  /// The target and Bluetooth address are rechecked immediately before use.
  Future<void> testComputerLaunch(
    ComputerTarget target,
    String applicationId,
    String chord,
  ) async {
    final application = computerApplicationById(applicationId);
    if (application == null ||
        !computerShortcutsFor(
          application.category,
        ).any((shortcut) => shortcut.id == 'launch')) {
      throw const FormatException('Choose an app with a launch action.');
    }
    if (!isComputerApplicationSupportedOn(
      application,
      activeComputer?.operatingSystem,
    )) {
      throw FormatException('${application.name} is unavailable on this OS.');
    }
    await _sendStandaloneChord(target, applicationId, 'launch', chord);
  }

  /// Send one configured or built-in shortcut to the computer currently
  /// selected in the app row. This method never routes a Desktop target over
  /// Bluetooth or an old shortcut set to another paired computer.
  Future<void> executeStandaloneShortcut(
    ComputerTarget target,
    String applicationId,
    String actionId,
  ) async {
    final current = activeComputer;
    final application = computerApplicationById(applicationId);
    if (current?.mode != ComputerMode.standalone ||
        current!.id != target.id ||
        target.mode != ComputerMode.standalone ||
        activeComputerSetup == null ||
        !activeComputerSetup!.applicationIds.contains(applicationId) ||
        application == null ||
        !isComputerApplicationSupportedOn(
          application,
          current.operatingSystem,
        ) ||
        !isStandaloneSetupComplete) {
      throw StateError('Select a configured app on its paired computer.');
    }
    final shortcut = computerShortcutsFor(application.category)
        .cast<ComputerShortcut?>()
        .firstWhere(
          (candidate) => candidate?.id == actionId,
          orElse: () => null,
        );
    if (shortcut == null) {
      throw FormatException('Unsupported ${application.name} action.');
    }
    final binding = activeComputerSetup!.bindingFor(applicationId, actionId);
    final chord =
        binding ?? defaultComputerShortcut(target, application, actionId);
    if (chord == null ||
        chord.trim().isEmpty ||
        parseComputerShortcut(chord) == null) {
      // The Home app selector invokes launch when a tile is selected. If no
      // launch key has been configured, leave the app controls open without
      // sending a key or surfacing an error; missing action keys stay disabled.
      if (actionId == 'launch') return;
      throw StateError(
        'Set ${shortcut.label} for ${application.name} in its setup.',
      );
    }
    await _sendStandaloneChord(target, applicationId, actionId, chord);
  }

  Future<void> _sendStandaloneChord(
    ComputerTarget target,
    String applicationId,
    String actionId,
    String chord,
  ) async {
    final action = parseComputerShortcut(chord);
    if (action == null) throw const FormatException('Invalid keyboard chord.');
    if (!_isCurrentStandaloneTarget(target)) {
      throw StateError(
        'Bluetooth disconnected or the selected computer changed.',
      );
    }
    final app = computerApplicationById(applicationId);
    if (app == null ||
        !computerShortcutsFor(
          app.category,
        ).any((shortcut) => shortcut.id == actionId)) {
      throw const FormatException('Unsupported app shortcut.');
    }
    await hid.sendStep(action);
    if (!_isCurrentStandaloneTarget(target)) {
      throw StateError('The Bluetooth computer changed while sending the key.');
    }
  }

  Future<void> _sendPinnedDesktopStep(HidAction action) async {
    if (_pinnedDesktopChoiceId == null ||
        action.type != ActionType.keyboard ||
        activeComputer?.mode != ComputerMode.advanced ||
        !isDesktopSynced) {
      return;
    }
    await _desktopShortcutHid.sendStep(action);
  }

  bool _isCurrentStandaloneTarget(ComputerTarget target) {
    final current = activeComputer;
    return target.mode == ComputerMode.standalone &&
        current?.mode == ComputerMode.standalone &&
        current!.id == target.id &&
        hid.connectionStatus.value == HidConnectionStatus.connected &&
        companion.activeHost.value == null;
  }

  bool get hasAcceptedDesktopSession {
    final host = companion.activeHost.value;
    return host != null && _isAcceptedCompanionHost(host);
  }

  bool _isAcceptedCompanionHost(CompanionHost host) =>
      _acceptedCompanionSession != null &&
      _acceptedCompanionSession == _companionSessionId(host);

  static String _companionSessionId(CompanionHost host) =>
      '${host.address}:${host.port}:${host.token}';

  String _desktopComputerSetupId(CompanionHost host) {
    final stableId = _acceptedCompanionComputerId?.trim();
    final identity =
        stableId != null &&
            RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(stableId)
        ? stableId
        : '${host.platform}:${host.name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
    return 'desktop:$identity';
  }

  ComputerOperatingSystem? _standaloneOperatingSystem(
    HidHost host,
    String targetId,
  ) {
    final saved = config.computerSetups[targetId]?.operatingSystem;
    if (saved != null) return saved;
    return _computerOperatingSystemHint(host.name);
  }

  ShortcutPlatform _standaloneShortcutPlatform(HidHost host) {
    final targetId = _bluetoothComputerSetupId(host);
    final saved = config.computerSetups[targetId]?.operatingSystem;
    if (saved != null) {
      return saved == ComputerOperatingSystem.macos
          ? ShortcutPlatform.apple
          : ShortcutPlatform.windowsLinux;
    }
    final configured = config.preferences.shortcutPlatform;
    if (configured != ShortcutPlatform.automatic) return configured;
    final hint = _computerOperatingSystemHint(host.name);
    if (hint != null) {
      return hint == ComputerOperatingSystem.macos
          ? ShortcutPlatform.apple
          : ShortcutPlatform.windowsLinux;
    }
    return detectShortcutPlatform(host.name);
  }

  static ComputerOperatingSystem? _computerOperatingSystemFromPlatform(
    String platform,
  ) => switch (platform.trim().toLowerCase()) {
    'windows' || 'win32' || 'win' => ComputerOperatingSystem.windows,
    'linux' => ComputerOperatingSystem.linux,
    'macos' || 'macosx' || 'darwin' || 'osx' => ComputerOperatingSystem.macos,
    _ => null,
  };

  static ComputerOperatingSystem? _computerOperatingSystemHint(
    String hostName,
  ) {
    final name = hostName.trim().toLowerCase();
    if (name.contains('macbook') ||
        name.contains('imac') ||
        name.contains('mac mini') ||
        name.contains('mac studio') ||
        name.contains('apple') ||
        RegExp(r'(^|[^a-z])mac([^a-z]|$)').hasMatch(name)) {
      return ComputerOperatingSystem.macos;
    }
    if (name.contains('ubuntu') ||
        name.contains('debian') ||
        name.contains('fedora') ||
        name.contains('linux') ||
        name.contains('arch linux')) {
      return ComputerOperatingSystem.linux;
    }
    if (name.contains('windows') ||
        RegExp(r'(^|[^a-z])win(dows)?([^a-z]|$)').hasMatch(name)) {
      return ComputerOperatingSystem.windows;
    }
    return null;
  }

  static String _bluetoothComputerSetupId(HidHost host) {
    final identity = host.address.trim().isEmpty
        ? host.id.trim()
        : host.address.trim().toLowerCase();
    return 'bluetooth:$identity';
  }

  static bool _sameComputerChord(String? first, String? second) {
    if (first == null || second == null) return false;
    final parsedFirst = parseComputerShortcut(first);
    final parsedSecond = parseComputerShortcut(second);
    if (parsedFirst == null || parsedSecond == null) return false;
    final firstModifiers = parsedFirst.modifiers.toSet();
    final secondModifiers = parsedSecond.modifiers.toSet();
    return parsedFirst.keyCode == parsedSecond.keyCode &&
        firstModifiers.length == secondModifiers.length &&
        firstModifiers.containsAll(secondModifiers);
  }

  static String _computerChordIdentity(String chord) {
    final action = parseComputerShortcut(chord)!;
    final modifiers = action.modifiers.toList()..sort();
    return '${action.keyCode}+${modifiers.join('+')}';
  }

  ComputerApplication? _computerApplicationFor(
    ComputerTarget target,
    String id,
  ) {
    final catalogApp = computerApplicationById(id);
    if (catalogApp != null || target.mode != ComputerMode.advanced) {
      return catalogApp;
    }
    final installed = desktopManifest?.applications
        .cast<RemoteApplication?>()
        .firstWhere((application) => application?.id == id, orElse: () => null);
    if (!isDesktopSynced || installed?.detected != true) return null;
    return ComputerApplication(
      id: installed!.id,
      name: installed.name,
      category: ComputerAppCategory.other,
    );
  }

  /// A retained manifest is intentionally kept for diagnostics after a LAN
  /// timeout. It is not an active Desktop sync and must not drive the surface.
  bool get isDesktopSynced =>
      companion.activeHost.value != null &&
      companion.syncStatus.value == CompanionSyncStatus.ready &&
      desktopManifest != null;
  bool get isDesktopDriven => isDesktopSynced;
  RemoteShortcutLayout? get remoteCurrentLayout =>
      desktopManifest?.currentLayout;
  RemoteShortcutLayout? get remoteCodexLayout =>
      desktopManifest?.layouts.cast<RemoteShortcutLayout?>().firstWhere(
        (layout) => layout?.kind == RemoteLayoutKind.codex,
        orElse: () => null,
      );
  RemoteShortcutLayout? vibeCodingLayoutFor(String applicationId) =>
      desktopManifest?.layoutById('vibe.$applicationId');
  List<RemoteApplication> get syncedApplications {
    final manifest = desktopManifest;
    if (!isDesktopSynced ||
        manifest == null ||
        !manifest.settings.enableAppsSync) {
      return const [];
    }
    return manifest.applications
        .where((application) => application.detected)
        .toList(growable: false);
  }

  List<RemoteApplication> get runningApplications => syncedApplications
      .where((application) => application.running)
      .toList(growable: false);

  bool get hasAppsSync => syncedApplications.isNotEmpty;
  RemoteApplication? get foregroundApplication =>
      syncedApplications.cast<RemoteApplication?>().firstWhere(
        (application) => application?.foreground == true,
        orElse: () => null,
      );

  RemoteShortcutLayout? get genericSyncedLayout =>
      isDesktopSynced ? desktopManifest?.currentLayout : null;

  RemoteShortcutLayout? get foregroundApplicationLayout {
    final application = foregroundApplication;
    if (application == null) return null;
    final layout = layoutForApplication(application);
    return layout == null || layout.buttons.isEmpty ? null : layout;
  }

  bool get hasCodexWorkspace =>
      syncedApplications.any((application) => application.id == 'codex') &&
      remoteCodexLayout != null;

  ControlSurfaceStatus get controlSurfaceStatus {
    final foreground = foregroundApplication;
    final foregroundStatus = !isDesktopSynced
        ? ForegroundWorkspaceStatus.unavailable
        : foreground == null
        ? ForegroundWorkspaceStatus.unknown
        : foregroundApplicationLayout == null
        ? ForegroundWorkspaceStatus.unavailableActions
        : ForegroundWorkspaceStatus.ready;
    final preferredSurface = foregroundStatus == ForegroundWorkspaceStatus.ready
        ? PreferredControlSurface.foregroundApplication
        : isDesktopSynced
        ? PreferredControlSurface.syncedGeneric
        : PreferredControlSurface.localGeneric;
    return ControlSurfaceStatus(
      hidConnected: hid.connectionStatus.value == HidConnectionStatus.connected,
      desktopDiscovered: companion.activeHost.value != null,
      desktopSynced: isDesktopSynced,
      foregroundStatus: foregroundStatus,
      preferredSurface: preferredSurface,
      foregroundApplicationName: foreground?.name,
    );
  }

  RemoteShortcutLayout? layoutForApplication(RemoteApplication application) =>
      desktopManifest?.layoutById(application.layoutId);
  List<ProfileConfig> get orderedProfiles {
    final byId = {for (final profile in config.profiles) profile.id: profile};
    return config.profileOrder
        .map((id) => byId[id])
        .whereType<ProfileConfig>()
        .toList(growable: false);
  }

  /// Desktop layouts replace the Web/meeting/custom phone tabs while synced.
  /// General remains available as the explicit Bluetooth HID fallback.
  List<ProfileConfig> get visibleHomeProfiles {
    final profiles = orderedProfiles;
    if (!isDesktopSynced) return profiles;
    final general = profiles
        .where(
          (profile) =>
              profile.id == 'profile_general' ||
              profile.name.trim().toLowerCase() == 'general',
        )
        .toList(growable: false);
    return general.isEmpty && profiles.isNotEmpty ? [profiles.first] : general;
  }

  ShortcutPlatform get effectiveShortcutPlatform {
    final desktop = companion.activeHost.value;
    if (desktop != null) {
      final operatingSystem = _computerOperatingSystemFromPlatform(
        desktop.platform,
      );
      if (operatingSystem != null) {
        return operatingSystem == ComputerOperatingSystem.macos
            ? ShortcutPlatform.apple
            : ShortcutPlatform.windowsLinux;
      }
      return desktop.isApple
          ? ShortcutPlatform.apple
          : ShortcutPlatform.windowsLinux;
    }
    final bluetoothHost = hid.activeHost.value;
    if (bluetoothHost != null &&
        hid.connectionStatus.value == HidConnectionStatus.connected) {
      return _standaloneShortcutPlatform(bluetoothHost);
    }
    final configured = config.preferences.shortcutPlatform;
    if (configured != ShortcutPlatform.automatic) return configured;
    return detectShortcutPlatform(hid.activeHost.value?.name);
  }

  String get primaryShortcutLabel =>
      effectiveShortcutPlatform == ShortcutPlatform.apple ? 'Command' : 'Ctrl';

  static ShortcutPlatform detectShortcutPlatform(String? hostName) {
    final name = hostName?.trim().toLowerCase() ?? '';
    if (name.contains('macbook') ||
        name.contains('imac') ||
        name.contains('mac mini') ||
        name.contains('mac studio') ||
        name.contains('iphone') ||
        name.contains('ipad') ||
        name.contains('apple') ||
        RegExp(r'(^|[^a-z])mac([^a-z]|$)').hasMatch(name)) {
      return ShortcutPlatform.apple;
    }
    return ShortcutPlatform.windowsLinux;
  }

  String resolveShortcutLabel(ButtonConfig button) {
    if (!button.action.modifiers.any(
      (modifier) => modifier.toUpperCase() == primaryShortcutModifier,
    )) {
      return button.subtitle;
    }
    final primary = effectiveShortcutPlatform == ShortcutPlatform.apple
        ? '⌘'
        : 'Ctrl';
    return button.subtitle.replaceFirst(
      RegExp(
        r'^(Ctrl|Control|Command|Cmd|⌘|Primary)(?=\+)',
        caseSensitive: false,
      ),
      primary,
    );
  }

  Future<void> initialize() async {
    try {
      _config = await repository.load();
      try {
        await shortcutUsage.load();
      } catch (_) {
        // Usage is optional; a storage failure must not disable the controls.
      }
      await orientationService.apply(config.preferences.orientationMode);
      await powerBrightnessService.initialize();
      await companion.start();
      await _applyChargingDisplayState();
    } catch (error) {
      _error = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void registerLayoutOrientation(bool landscape) {
    if (_lastLandscape == null) {
      _lastLandscape = landscape;
      return;
    }
    if (_lastLandscape == landscape) return;
    _lastLandscape = landscape;
    _pressedPositions.clear();
    _pressedButtonActions.clear();
    _pressedWheelCenterAction = null;
    _touchpadScrollAccumulator = 0;
    _inputEpoch++;
    unawaited(
      hid.releaseAllKeys().catchError((Object error) {
        _error = error;
      }),
    );
  }

  Future<void> prepareForContextChange() async {
    _pressedPositions.clear();
    _pressedButtonActions.clear();
    _pressedWheelCenterAction = null;
    _touchpadScrollAccumulator = 0;
    _inputEpoch++;
    notifyListeners();
    try {
      await hid.releaseAllKeys();
    } catch (error) {
      _error = error;
      notifyListeners();
    }
  }

  Future<void> switchProfile(String profileId) async {
    if (profileId == config.activeProfileId ||
        !config.profiles.any((profile) => profile.id == profileId)) {
      return;
    }
    final safety = prepareForContextChange();
    _config = config.copyWith(activeProfileId: profileId);
    notifyListeners();
    await Future.wait([safety, repository.save(config)]);
  }

  Future<void> switchProfileByOffset(int offset) async {
    final profiles = orderedProfiles;
    if (profiles.length < 2 || offset == 0) return;
    final currentIndex = profiles.indexWhere(
      (profile) => profile.id == config.activeProfileId,
    );
    final nextIndex = (currentIndex + offset) % profiles.length;
    await switchProfile(profiles[nextIndex].id);
  }

  Future<void> pressButton(ButtonConfig button) async {
    if (_computerSwitchPendingId != null) return;
    if (button.action.type == ActionType.none) return;
    if (_pinnedDesktopChoiceId != null) {
      if (button.action.type == ActionType.keyboard) {
        await _sendPinnedDesktopStep(_resolveShortcutAction(button.action));
      }
      return;
    }
    _recordShortcutUsage(
      _localButtonUsageKey(activeProfile, button),
      '${activeProfile.name} · ${button.label}',
      action: button.action,
    );
    if (_isDarkAction(button.action)) {
      if (config.preferences.hapticEnabled && button.hapticEnabled) {
        unawaited(HapticFeedback.lightImpact());
      }
      if (config.preferences.soundEnabled && button.soundEnabled) {
        unawaited(SystemSound.play(SystemSoundType.click));
      }
      await _toggleDarkMode();
      notifyListeners();
      return;
    }
    if (button.action.type == ActionType.companion) {
      if (config.preferences.hapticEnabled && button.hapticEnabled) {
        unawaited(HapticFeedback.lightImpact());
      }
      await companion.execute(button.action.value ?? '{}');
      notifyListeners();
      return;
    }
    final resolvedAction = _resolveShortcutAction(button.action);
    _pressedPositions.add(button.position);
    _pressedButtonActions[button.position] = resolvedAction;
    notifyListeners();
    if (config.preferences.hapticEnabled && button.hapticEnabled) {
      unawaited(HapticFeedback.lightImpact());
    }
    if (config.preferences.soundEnabled && button.soundEnabled) {
      unawaited(SystemSound.play(SystemSoundType.click));
    }
    await hid.sendPress(resolvedAction);
  }

  Future<void> executeRemoteButton(RemoteShortcutButton button) async {
    if (_computerSwitchPendingId != null) return;
    _recordShortcutUsage('desktop:button:${button.id}', button.name);
    await companion.executeRemote(RemoteActionRequest.button(button.id));
  }

  Future<void> executeVibeCodingButton(
    String applicationId,
    String buttonId,
  ) async {
    final layout = vibeCodingLayoutFor(applicationId);
    final button = layout?.buttons.cast<RemoteShortcutButton?>().firstWhere(
      (candidate) => candidate?.id == buttonId,
      orElse: () => null,
    );
    if (!isDesktopSynced ||
        layout == null ||
        !desktopManifest!.settings.enableAppsSync ||
        desktopManifest!.applicationById(applicationId)?.detected != true ||
        button == null ||
        !button.id.startsWith('vibe.$applicationId.') ||
        !button.enabled) {
      return;
    }
    await executeRemoteButton(button);
  }

  Future<void> launchRemoteApplication(RemoteApplication application) async {
    if (_computerSwitchPendingId != null) return;
    _recordShortcutUsage(
      'desktop:app:${application.id}',
      'Open ${application.name}',
    );
    await companion.executeRemote(
      RemoteActionRequest.launchApplication(application.id),
    );
  }

  Future<void> launchVibeCodingApplication(String applicationId) async {
    final manifest = desktopManifest;
    final application = manifest?.applicationById(applicationId);
    if (!isDesktopSynced ||
        manifest == null ||
        !manifest.settings.enableAppsSync ||
        vibeCodingLayoutFor(applicationId) == null ||
        application?.detected != true) {
      return;
    }
    await launchRemoteApplication(application!);
  }

  Future<void> switchRemoteProfile(RemoteProfile profile) =>
      companion.executeRemote(RemoteActionRequest.switchProfile(profile.id));

  Future<void> releaseButton(ButtonConfig button) async {
    if (!_pressedPositions.remove(button.position)) return;
    final resolvedAction = _pressedButtonActions.remove(button.position);
    notifyListeners();
    if (resolvedAction != null) {
      await hid.sendRelease(resolvedAction);
    }
  }

  Future<void> sendWheelStep(bool clockwise) async {
    if (_computerSwitchPendingId != null) return;
    final action = clockwise
        ? activeProfile.wheel.clockwise
        : activeProfile.wheel.counterClockwise;
    if (action.type != ActionType.none) {
      if (_pinnedDesktopChoiceId != null) {
        if (action.type == ActionType.keyboard) {
          await _sendPinnedDesktopStep(_resolveShortcutAction(action));
        }
        return;
      }
      _recordShortcutUsage(
        'local:${activeProfile.id}:wheel:${clockwise ? 'clockwise' : 'counterClockwise'}',
        '${activeProfile.name} · ${clockwise ? 'Wheel clockwise' : 'Wheel counter-clockwise'}',
        action: action,
      );
      await hid.sendStep(_resolveShortcutAction(action));
    }
  }

  Future<void> pressWheelCenter() async {
    if (_computerSwitchPendingId != null) return;
    final action = activeProfile.wheel.center;
    if (action.type != ActionType.none) {
      if (_pinnedDesktopChoiceId != null) {
        if (action.type == ActionType.keyboard) {
          await _sendPinnedDesktopStep(_resolveShortcutAction(action));
        }
        return;
      }
      _recordShortcutUsage(
        'local:${activeProfile.id}:wheel:center',
        '${activeProfile.name} · Wheel center',
        action: action,
      );
      final resolvedAction = _resolveShortcutAction(action);
      _pressedWheelCenterAction = resolvedAction;
      await hid.sendPress(resolvedAction);
    }
  }

  Future<void> releaseWheelCenter() async {
    final resolvedAction = _pressedWheelCenterAction;
    _pressedWheelCenterAction = null;
    if (resolvedAction != null) await hid.sendRelease(resolvedAction);
  }

  void sendTouchpadMove(double deltaX, double deltaY) {
    if (_computerSwitchPendingId != null) return;
    if (_pinnedDesktopChoiceId != null) return;
    const sensitivity = 1.65;
    final x = (deltaX * sensitivity).round().clamp(-127, 127);
    final y = (deltaY * sensitivity).round().clamp(-127, 127);
    if (x == 0 && y == 0) return;
    unawaited(
      hid.sendPress(HidAction(type: ActionType.mouseMove, value: '$x,$y')),
    );
  }

  void sendMouseClick({required bool secondary}) {
    if (_computerSwitchPendingId != null) return;
    if (_pinnedDesktopChoiceId != null) return;
    if (config.preferences.hapticEnabled) {
      unawaited(HapticFeedback.selectionClick());
    }
    unawaited(
      hid.sendStep(
        HidAction(
          type: ActionType.mouseButton,
          value: secondary ? 'RIGHT' : 'LEFT',
        ),
      ),
    );
  }

  void sendPrimaryMouseClick() => sendMouseClick(secondary: false);

  void sendSecondaryMouseClick() => sendMouseClick(secondary: true);

  void sendTouchpadScroll(double deltaY) {
    const pixelsPerWheelStep = 12.0;
    _touchpadScrollAccumulator += deltaY;
    final steps = (_touchpadScrollAccumulator / pixelsPerWheelStep).truncate();
    if (steps == 0) return;
    _touchpadScrollAccumulator -= steps * pixelsPerWheelStep;
    final wheelDelta = (-steps).clamp(-127, 127);
    unawaited(
      hid.sendStep(
        HidAction(type: ActionType.mouseWheel, value: '$wheelDelta'),
      ),
    );
  }

  HidAction _resolveShortcutAction(HidAction action) {
    if (action.type != ActionType.keyboard) return action;
    final primary = effectiveShortcutPlatform == ShortcutPlatform.apple
        ? 'LEFT_META'
        : 'LEFT_CTRL';
    return action.copyWith(
      modifiers: action.modifiers
          .map(
            (modifier) => modifier.toUpperCase() == primaryShortcutModifier
                ? primary
                : modifier,
          )
          .toList(growable: false),
    );
  }

  static bool _isDarkAction(HidAction action) {
    if (action.type != ActionType.companion || action.value == null) {
      return false;
    }
    try {
      final decoded = jsonDecode(action.value!);
      return decoded is Map && decoded['kind'] == 'dark';
    } on FormatException {
      return false;
    }
  }

  Future<void> _toggleDarkMode() async {
    _darkModeActive = !_darkModeActive;
    final enabled = _darkModeActive;
    notifyListeners();

    final transition = _darkTransition.then(
      (_) => _applyDarkTransition(enabled),
      onError: (_, _) => _applyDarkTransition(enabled),
    );
    _darkTransition = transition;
    await transition;
  }

  Future<void> _applyDarkTransition(bool enabled) async {
    if (enabled) {
      await powerBrightnessService.setAppBrightness(_darkPhoneBrightness);
    } else {
      await _applyChargingDisplayState();
    }

    final hostTasks = <Future<void>>[];
    if (_pinnedDesktopChoiceId == null &&
        hid.connectionStatus.value == HidConnectionStatus.connected) {
      hostTasks.add(_setHostDarkThroughHid(enabled));
    }
    if (companion.activeHost.value != null) {
      hostTasks.add(
        companion.execute(jsonEncode({'kind': 'dark', 'enabled': enabled})),
      );
    }
    await Future.wait(hostTasks);
  }

  Future<void> _setHostDarkThroughHid(bool enabled) async {
    const displayDown = HidAction(
      type: ActionType.consumerControl,
      value: 'BRIGHTNESS_DOWN',
    );
    const displayUp = HidAction(
      type: ActionType.consumerControl,
      value: 'BRIGHTNESS_UP',
    );
    const keyboardDown = HidAction(
      type: ActionType.consumerControl,
      value: 'KEYBOARD_BRIGHTNESS_DOWN',
    );
    const keyboardUp = HidAction(
      type: ActionType.consumerControl,
      value: 'KEYBOARD_BRIGHTNESS_UP',
    );
    const keyboardMinimum = HidAction(
      type: ActionType.consumerControl,
      value: 'KEYBOARD_BACKLIGHT_MINIMUM',
    );
    const keyboardMaximum = HidAction(
      type: ActionType.consumerControl,
      value: 'KEYBOARD_BACKLIGHT_MAXIMUM',
    );
    if (enabled) {
      for (var step = 0; step < _displayBrightnessDownSteps; step++) {
        await hid.sendStep(displayDown);
      }
      await hid.sendStep(keyboardMinimum);
      for (var step = 0; step < _keyboardBrightnessSteps; step++) {
        await hid.sendStep(keyboardDown);
      }
      return;
    }
    for (var step = 0; step < _displayBrightnessUpSteps; step++) {
      await hid.sendStep(displayUp);
    }
    await hid.sendStep(keyboardMaximum);
    for (var step = 0; step < _keyboardBrightnessSteps; step++) {
      await hid.sendStep(keyboardUp);
    }
  }

  void _rememberAcceptedCompanionSession() {
    final host = companion.activeHost.value;
    if (host != null && isDesktopSynced) {
      final sessionId = _companionSessionId(host);
      if (_acceptedCompanionSession != sessionId) {
        _acceptedCompanionSession = sessionId;
      }
      final computerId = desktopManifest?.computerId?.trim();
      _acceptedCompanionComputerId =
          computerId != null &&
              RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(computerId)
          ? computerId
          : null;
    }
  }

  void _handleCompanionHostChanged() {
    _rememberAcceptedCompanionSession();
    final choiceId = selectedDesktopComputerChoiceId;
    if (choiceId != null &&
        companion.activeHost.value != null &&
        companion is SwitchableCompanionConnection &&
        (companion as SwitchableCompanionConnection)
            .isComputerSelectionPinned) {
      _pinnedDesktopChoiceId = choiceId;
    }
    notifyListeners();
  }

  void _handleCompanionManifestChanged() {
    _rememberAcceptedCompanionSession();
    notifyListeners();
  }

  Future<void> updateOrientationMode(OrientationMode mode) async {
    _config = config.copyWith(
      preferences: config.preferences.copyWith(orientationMode: mode),
    );
    notifyListeners();
    await Future.wait([
      orientationService.apply(mode),
      repository.save(config),
    ]);
  }

  Future<void> updateShortcutPlatform(ShortcutPlatform platform) async {
    await prepareForContextChange();
    _config = config.copyWith(
      preferences: config.preferences.copyWith(shortcutPlatform: platform),
    );
    notifyListeners();
    await repository.save(config);
  }

  Future<void> setBeginnerMode(bool beginnerMode) async {
    if (config.preferences.beginnerMode == beginnerMode) return;
    _config = config.copyWith(
      preferences: config.preferences.copyWith(beginnerMode: beginnerMode),
    );
    notifyListeners();
    var saved = config;
    await repository.save(saved);
    while (!identical(_config, saved)) {
      saved = config;
      await repository.save(saved);
    }
  }

  Future<void> updateControlSurfaceLayout(ControlSurfaceLayout value) async {
    await prepareForContextChange();
    _config = config.copyWith(
      preferences: config.preferences.copyWith(controlSurfaceLayout: value),
    );
    notifyListeners();
    await repository.save(config);
  }

  Future<void> updateTabletKeysPerPage(int value) async {
    if (value < minTabletKeysPerPage || value > maxTabletKeysPerPage) {
      throw ArgumentError.value(
        value,
        'value',
        'Must be between $minTabletKeysPerPage and $maxTabletKeysPerPage.',
      );
    }
    await prepareForContextChange();
    _config = config.copyWith(
      preferences: config.preferences.copyWith(tabletKeysPerPage: value),
    );
    notifyListeners();
    await repository.save(config);
  }

  Future<void> updateFeedbackPreferences({
    bool? hapticEnabled,
    bool? soundEnabled,
  }) async {
    _config = config.copyWith(
      preferences: config.preferences.copyWith(
        hapticEnabled: hapticEnabled,
        soundEnabled: soundEnabled,
      ),
    );
    notifyListeners();
    await repository.save(config);
  }

  Future<void> updateChargingBrightness({
    ChargingBrightnessMode? mode,
    double? brightness,
    bool? keepScreenOn,
  }) async {
    _darkModeActive = false;
    _config = config.copyWith(
      preferences: config.preferences.copyWith(
        chargingBrightnessMode: mode,
        chargingBrightness: brightness,
        keepScreenOnWhileCharging: keepScreenOn,
      ),
    );
    notifyListeners();
    await Future.wait([repository.save(config), _applyChargingDisplayState()]);
  }

  Future<void> handleAppResumed() async {
    await powerBrightnessService.refreshPowerState();
    await _applyChargingDisplayState();
  }

  void _handlePowerChanged() {
    notifyListeners();
    unawaited(_applyChargingDisplayState());
  }

  Future<void> _applyChargingDisplayState() async {
    final preferences = config.preferences;
    final pluggedIn = powerBrightnessService.isPluggedIn.value == true;
    final fixedWhileCharging =
        pluggedIn &&
        preferences.chargingBrightnessMode == ChargingBrightnessMode.fixed;
    await Future.wait([
      powerBrightnessService.setAppBrightness(
        _darkModeActive
            ? _darkPhoneBrightness
            : fixedWhileCharging
            ? preferences.chargingBrightness
            : null,
      ),
      powerBrightnessService.setKeepScreenOn(
        pluggedIn && preferences.keepScreenOnWhileCharging,
      ),
    ]);
  }

  Future<void> updateButton(ButtonConfig updated) async {
    if (updated.position < 0 || updated.position >= maxControlButtonCount) {
      return;
    }
    final profile = activeProfile;
    final buttons = [...profile.buttons];
    final index = buttons.indexWhere(
      (button) => button.position == updated.position,
    );
    if (index < 0) {
      while (buttons.length <= updated.position) {
        buttons.add(ButtonConfig.empty(buttons.length));
      }
      buttons[updated.position] = updated;
    } else {
      buttons[index] = updated;
    }
    buttons.sort((a, b) => a.position.compareTo(b.position));
    await _replaceProfile(
      profile.copyWith(
        buttons: buttons,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> swapButtons(int sourcePosition, int targetPosition) async {
    if (sourcePosition == targetPosition) return;
    if (sourcePosition < 0 ||
        sourcePosition >= maxControlButtonCount ||
        targetPosition < 0 ||
        targetPosition >= maxControlButtonCount) {
      return;
    }
    final profile = activeProfile;
    final byPosition = {
      for (final button in profile.buttons)
        if (button.position >= 0 && button.position < maxControlButtonCount)
          button.position: button,
    };
    final lastPosition = [
      sourcePosition,
      targetPosition,
      ...byPosition.keys,
    ].reduce((a, b) => a > b ? a : b);
    final buttons = List.generate(
      lastPosition + 1,
      (position) => byPosition[position] ?? ButtonConfig.empty(position),
    );
    final source = buttons[sourcePosition];
    final target = buttons[targetPosition];
    buttons[sourcePosition] = _moveButtonToPosition(target, sourcePosition);
    buttons[targetPosition] = _moveButtonToPosition(source, targetPosition);
    await _replaceProfile(
      profile.copyWith(
        buttons: buttons,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  int usageCountForButton(ProfileConfig profile, ButtonConfig button) =>
      shortcutUsage.countFor(_localButtonUsageKey(profile, button));

  Future<void> reorderActiveProfileByUsage() async {
    final profile = activeProfile;
    final ordered = [...profile.buttons]
      ..sort((a, b) {
        final aEmpty = a.action.type == ActionType.none;
        final bEmpty = b.action.type == ActionType.none;
        if (aEmpty != bEmpty) return aEmpty ? 1 : -1;
        final byUsage = usageCountForButton(
          profile,
          b,
        ).compareTo(usageCountForButton(profile, a));
        return byUsage != 0 ? byUsage : a.position.compareTo(b.position);
      });
    final repositioned = [
      for (var position = 0; position < ordered.length; position++)
        _moveButtonToPosition(ordered[position], position),
    ];
    await _replaceProfile(
      profile.copyWith(
        buttons: repositioned,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static String _localButtonUsageKey(
    ProfileConfig profile,
    ButtonConfig button,
  ) {
    final action = button.action;
    final modifiers = [...action.modifiers]..sort();
    return [
      'local',
      profile.id,
      action.type.name,
      action.keyCode ?? '',
      modifiers.join(','),
      action.value ?? '',
      button.label,
    ].join(':');
  }

  void _recordShortcutUsage(String key, String label, {HidAction? action}) {
    unawaited(
      shortcutUsage
          .record(
            key,
            label,
            publicShortcutId: action == null
                ? null
                : publicShortcutIdForAction(action),
          )
          .catchError((Object _) {}),
    );
  }

  static ButtonConfig _moveButtonToPosition(
    ButtonConfig button,
    int position,
  ) => button.copyWith(
    id: 'button_${(position + 1).toString().padLeft(2, '0')}',
    position: position,
  );

  Future<void> updateWheel(WheelConfig wheel) => _replaceProfile(
    activeProfile.copyWith(
      wheel: wheel,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  void copyButton(ButtonConfig button) {
    _buttonClipboard = button;
    notifyListeners();
  }

  Future<void> pasteButton(int position) async {
    final copied = _buttonClipboard;
    if (copied == null) return;
    await updateButton(
      copied.copyWith(
        id: 'button_${(position + 1).toString().padLeft(2, '0')}',
        position: position,
      ),
    );
  }

  Future<void> resetButton(int position) async {
    if (position < 0 || position >= maxControlButtonCount) return;
    final builtIns = await templates.loadAll();
    final template = builtIns
        .where((item) => item.id == activeProfile.id)
        .firstOrNull;
    await updateButton(
      template != null && position < template.buttons.length
          ? template.buttons[position]
          : ButtonConfig.empty(position),
    );
  }

  Future<void> clearButton(int position) => updateButton(
    ButtonConfig.empty(position).copyWith(
      label: '',
      visual: const ButtonVisual(),
      action: const HidAction(),
    ),
  );

  Future<ProfileConfig> createProfile({String name = 'New Profile'}) async {
    _ensureCanAddProfile();
    final now = DateTime.now().millisecondsSinceEpoch;
    final profile = ProfileConfig(
      id: _nextProfileId(),
      name: name,
      buttons: List.generate(controlButtonCount, ButtonConfig.empty),
      wheel: const WheelConfig(),
      createdAt: now,
      updatedAt: now,
    );
    _config = config.copyWith(
      profiles: [...config.profiles, profile],
      profileOrder: [...config.profileOrder, profile.id],
    );
    notifyListeners();
    await repository.save(config);
    return profile;
  }

  Future<ProfileConfig> duplicateProfile(ProfileConfig source) async {
    _ensureCanAddProfile();
    final now = DateTime.now().millisecondsSinceEpoch;
    final copy = source.copyWith(
      id: _nextProfileId(),
      name: '${source.name} Copy',
      isBuiltInTemplate: false,
      createdAt: now,
      updatedAt: now,
    );
    _config = config.copyWith(
      profiles: [...config.profiles, copy],
      profileOrder: [...config.profileOrder, copy.id],
    );
    notifyListeners();
    await repository.save(config);
    return copy;
  }

  Future<void> renameProfile(ProfileConfig profile, String name) =>
      _replaceProfile(
        profile.copyWith(
          name: name.trim(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  Future<void> updateProfileAppearance(
    ProfileConfig profile, {
    ButtonVisual? icon,
    int? accentColor,
  }) => _replaceProfile(
    profile.copyWith(
      profileIcon: icon,
      accentColor: accentColor,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  Future<void> updateProfileDetails(
    ProfileConfig profile, {
    required String name,
    String? targetApplication,
    required ButtonVisual icon,
    required int? accentColor,
  }) => _replaceProfile(
    profile.copyWith(
      name: name.trim(),
      targetApplication: targetApplication,
      clearTargetApplication:
          targetApplication == null || targetApplication.trim().isEmpty,
      profileIcon: icon,
      accentColor: accentColor,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );

  Future<void> setDefaultProfile(String profileId) async {
    _config = config.copyWith(defaultProfileId: profileId);
    notifyListeners();
    await repository.save(config);
  }

  Future<void> deleteProfile(String profileId) async {
    if (config.profiles.length <= 1) {
      throw StateError('At least one profile must remain.');
    }
    final profiles = config.profiles
        .where((profile) => profile.id != profileId)
        .toList();
    final order = config.profileOrder.where((id) => id != profileId).toList();
    var defaultId = config.defaultProfileId;
    if (defaultId == profileId) defaultId = order.first;
    var activeId = config.activeProfileId;
    if (activeId == profileId) {
      await prepareForContextChange();
      activeId = defaultId;
    }
    _config = config.copyWith(
      profiles: profiles,
      profileOrder: order,
      defaultProfileId: defaultId,
      activeProfileId: activeId,
    );
    notifyListeners();
    await repository.save(config);
    await imageStore.cleanupUnreferenced(config);
  }

  Future<void> reorderProfiles(int oldIndex, int newIndex) async {
    final order = [...config.profileOrder];
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    _config = config.copyWith(profileOrder: order);
    notifyListeners();
    await repository.save(config);
  }

  Future<void> importProfile(
    ProfileConfig profile, {
    String? replaceProfileId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (replaceProfileId != null) {
      final target = config.profiles
          .where((item) => item.id == replaceProfileId)
          .firstOrNull;
      if (target == null) {
        throw StateError('The selected profile slot no longer exists.');
      }
      if (target.id == config.activeProfileId) {
        await prepareForContextChange();
      }
      final replacement = profile.copyWith(
        id: target.id,
        isBuiltInTemplate: false,
        createdAt: target.createdAt,
        updatedAt: now,
      );
      _config = config.copyWith(
        profiles: config.profiles
            .map((item) => item.id == target.id ? replacement : item)
            .toList(growable: false),
      );
    } else {
      _ensureCanAddProfile();
      final imported = profile.copyWith(
        id: _nextProfileId(),
        isBuiltInTemplate: false,
        createdAt: now,
        updatedAt: now,
      );
      _config = config.copyWith(
        profiles: [...config.profiles, imported],
        profileOrder: [...config.profileOrder, imported.id],
      );
    }
    notifyListeners();
    await repository.save(config);
    await imageStore.cleanupUnreferenced(config);
  }

  Future<void> restoreTemplate(String templateId) async {
    final builtIns = await templates.loadAll();
    final template = builtIns.firstWhere((item) => item.id == templateId);
    final profiles = [...config.profiles];
    final index = profiles.indexWhere((item) => item.id == templateId);
    if (index >= 0) {
      profiles[index] = template;
    } else {
      _ensureCanAddProfile();
      profiles.add(template);
    }
    final order = config.profileOrder.contains(templateId)
        ? config.profileOrder
        : [...config.profileOrder, templateId];
    _config = config.copyWith(profiles: profiles, profileOrder: order);
    notifyListeners();
    await repository.save(config);
  }

  Future<void> restoreAllTemplates() async {
    final profiles = (await templates.loadAll())
        .take(freeProfileLimit)
        .toList(growable: false);
    final order = profiles.map((item) => item.id).toList(growable: false);
    final activeId = profiles.any((item) => item.id == config.activeProfileId)
        ? config.activeProfileId
        : profiles.first.id;
    final defaultId = profiles.any((item) => item.id == config.defaultProfileId)
        ? config.defaultProfileId
        : profiles.first.id;
    _config = config.copyWith(
      profiles: profiles,
      profileOrder: order,
      activeProfileId: activeId,
      defaultProfileId: defaultId,
    );
    notifyListeners();
    await repository.save(config);
  }

  /// Applies a reviewed account snapshot without invoking Desktop or HID
  /// actions. Configuration is persisted before the visible state changes.
  Future<void> restoreAccountBackup(
    DecodedAccountBackup backup, {
    bool restoreSettings = true,
    Set<String>? profileIds,
    bool restoreImages = true,
  }) async {
    final selectedIds =
        profileIds ?? backup.profiles.map((item) => item.id).toSet();
    final incoming = backup.profiles
        .where((item) => selectedIds.contains(item.id))
        .toList();
    final incomingById = {for (final profile in incoming) profile.id: profile};
    final merged = [...config.profiles];
    for (final entry in incomingById.entries) {
      final index = merged.indexWhere((profile) => profile.id == entry.key);
      if (index >= 0) {
        merged[index] = entry.value;
      } else {
        merged.add(entry.value);
      }
    }
    if (merged.length > freeProfileLimit) {
      throw const ProfileLimitException();
    }

    final incomingImageRefs = <String>{};
    for (final profile in incoming) {
      if (profile.profileIcon.type == VisualType.customImage &&
          profile.profileIcon.value != null) {
        incomingImageRefs.add(profile.profileIcon.value!);
      }
      for (final button in profile.buttons) {
        if (button.visual.type == VisualType.customImage &&
            button.visual.value != null) {
          incomingImageRefs.add(button.visual.value!);
        }
      }
    }
    final selectedImageBytes = restoreImages
        ? Map<String, Uint8List>.fromEntries(
            backup.images.entries.where(
              (e) => incomingImageRefs.contains(e.key),
            ),
          )
        : <String, Uint8List>{};
    await prepareForContextChange();
    final imagePaths = await imageStore.writeRestoredImages(selectedImageBytes);
    final restoredProfiles = <ProfileConfig>[];
    late final AppConfig nextConfig;
    try {
      for (final profile in merged) {
        if (!incomingById.containsKey(profile.id)) {
          restoredProfiles.add(profile);
          continue;
        }
        restoredProfiles.add(
          await _resolveRestoredProfileImages(profile, imagePaths),
        );
      }
      final order = [...config.profileOrder];
      for (final profile in restoredProfiles) {
        if (!order.contains(profile.id)) order.add(profile.id);
      }
      final preferences = restoreSettings && backup.preferences != null
          ? backup.preferences!.copyWith(
              beginnerMode: config.preferences.beginnerMode,
            )
          : config.preferences;
      nextConfig = config.copyWith(
        profiles: restoredProfiles,
        profileOrder: order,
        preferences: preferences,
      );
      await repository.save(nextConfig);
    } catch (_) {
      await imageStore.deleteRestoredImages(imagePaths.values);
      rethrow;
    }
    _config = nextConfig;
    notifyListeners();
    if (restoreSettings && backup.preferences != null) {
      await orientationService.apply(nextConfig.preferences.orientationMode);
      await _applyChargingDisplayState();
    }
    await imageStore.cleanupUnreferenced(nextConfig);
  }

  Future<ProfileConfig> _resolveRestoredProfileImages(
    ProfileConfig profile,
    Map<String, String> imagePaths,
  ) async {
    Future<ButtonVisual> resolve(ButtonVisual visual) async {
      if (visual.type != VisualType.customImage || visual.value == null) {
        return visual;
      }
      final restored = imagePaths[visual.value];
      if (restored != null) return visual.copyWith(value: restored);
      final existing = await imageStore.resolve(visual.value);
      if (existing != null) return visual;
      return visual.copyWith(type: VisualType.none, clearValue: true);
    }

    final icon = await resolve(profile.profileIcon);
    final buttons = <ButtonConfig>[];
    for (final button in profile.buttons) {
      buttons.add(button.copyWith(visual: await resolve(button.visual)));
    }
    return profile.copyWith(profileIcon: icon, buttons: buttons);
  }

  Future<void> _replaceProfile(ProfileConfig replacement) async {
    final profiles = config.profiles
        .map((profile) => profile.id == replacement.id ? replacement : profile)
        .toList();
    _config = config.copyWith(profiles: profiles);
    notifyListeners();
    await repository.save(config);
    unawaited(
      imageStore.cleanupUnreferenced(config).catchError((Object _) {
        // Image cleanup is housekeeping and must never block a saved edit.
      }),
    );
  }

  String _nextProfileId() {
    String candidate;
    do {
      candidate =
          'profile_${DateTime.now().microsecondsSinceEpoch}_${_profileIdSequence++}';
    } while (config.profiles.any((profile) => profile.id == candidate));
    return candidate;
  }

  void _ensureCanAddProfile() {
    if (!canAddProfile) throw const ProfileLimitException();
  }

  void _handleActiveHostChanged() {
    if (_pressedPositions.isNotEmpty || _pressedWheelCenterAction != null) {
      unawaited(prepareForContextChange());
    } else {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _computerSwitchEpoch++;
    hid.activeHost.removeListener(_handleActiveHostChanged);
    hid.connectionStatus.removeListener(_handleActiveHostChanged);
    hid.pairedHosts.removeListener(notifyListeners);
    companion.activeHost.removeListener(_handleCompanionHostChanged);
    companion.manifest.removeListener(_handleCompanionManifestChanged);
    companion.syncStatus.removeListener(_handleCompanionManifestChanged);
    companion.errorMessage.removeListener(_handleCompanionManifestChanged);
    desktopComputerChoices?.removeListener(notifyListeners);
    powerBrightnessService.isPluggedIn.removeListener(_handlePowerChanged);
    hid.dispose();
    if (!identical(_desktopShortcutHid, hid)) _desktopShortcutHid.dispose();
    companion.dispose();
    powerBrightnessService.dispose();
    shortcutUsage.dispose();
    super.dispose();
  }
}

class ProfileLimitException implements Exception {
  const ProfileLimitException();

  @override
  String toString() =>
      'The free version supports up to $freeProfileLimit profiles. Replace an existing profile to continue.';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
