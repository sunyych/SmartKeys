import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lumiakeys_protocol/lumiakeys_protocol.dart';

import '../data/config_repository.dart';
import '../data/private_image_store.dart';
import '../data/profile_template_repository.dart';
import '../data/shortcut_usage_repository.dart';
import '../models/config.dart';
import '../models/control_surface_status.dart';
import '../services/hid_service.dart';
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
  }) {
    hid.activeHost.addListener(_handleActiveHostChanged);
    hid.connectionStatus.addListener(_handleActiveHostChanged);
    companion.activeHost.addListener(_handleCompanionHostChanged);
    companion.manifest.addListener(_handleCompanionManifestChanged);
    companion.syncStatus.addListener(_handleCompanionManifestChanged);
    companion.errorMessage.addListener(_handleCompanionManifestChanged);
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

  AppConfig? _config;
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

  ShortcutPlatform get effectiveShortcutPlatform {
    final configured = config.preferences.shortcutPlatform;
    if (configured != ShortcutPlatform.automatic) return configured;
    final desktop = companion.activeHost.value;
    if (desktop != null) {
      return desktop.isApple
          ? ShortcutPlatform.apple
          : ShortcutPlatform.windowsLinux;
    }
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
      await shortcutUsage.load();
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
    if (button.action.type == ActionType.none) return;
    _recordShortcutUsage(
      _localButtonUsageKey(activeProfile, button),
      '${activeProfile.name} · ${button.label}',
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
    _recordShortcutUsage('desktop:button:${button.id}', button.name);
    await companion.executeRemote(RemoteActionRequest.button(button.id));
  }

  Future<void> launchRemoteApplication(RemoteApplication application) async {
    _recordShortcutUsage(
      'desktop:app:${application.id}',
      'Open ${application.name}',
    );
    await companion.executeRemote(
      RemoteActionRequest.launchApplication(application.id),
    );
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
    final action = clockwise
        ? activeProfile.wheel.clockwise
        : activeProfile.wheel.counterClockwise;
    if (action.type != ActionType.none) {
      _recordShortcutUsage(
        'local:${activeProfile.id}:wheel:${clockwise ? 'clockwise' : 'counterClockwise'}',
        '${activeProfile.name} · ${clockwise ? 'Wheel clockwise' : 'Wheel counter-clockwise'}',
      );
      await hid.sendStep(_resolveShortcutAction(action));
    }
  }

  Future<void> pressWheelCenter() async {
    final action = activeProfile.wheel.center;
    if (action.type != ActionType.none) {
      _recordShortcutUsage(
        'local:${activeProfile.id}:wheel:center',
        '${activeProfile.name} · Wheel center',
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
    const sensitivity = 1.65;
    final x = (deltaX * sensitivity).round().clamp(-127, 127);
    final y = (deltaY * sensitivity).round().clamp(-127, 127);
    if (x == 0 && y == 0) return;
    unawaited(
      hid.sendPress(HidAction(type: ActionType.mouseMove, value: '$x,$y')),
    );
  }

  void sendMouseClick({required bool secondary}) {
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
    if (hid.connectionStatus.value == HidConnectionStatus.connected) {
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

  void _handleCompanionHostChanged() => notifyListeners();

  void _handleCompanionManifestChanged() => notifyListeners();

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
    final profile = activeProfile;
    final buttons = [...profile.buttons];
    final index = buttons.indexWhere(
      (button) => button.position == updated.position,
    );
    if (index < 0) return;
    buttons[index] = updated;
    await _replaceProfile(
      profile.copyWith(
        buttons: buttons,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> swapButtons(int sourcePosition, int targetPosition) async {
    if (sourcePosition == targetPosition) return;
    final profile = activeProfile;
    final buttons = [...profile.buttons];
    final sourceIndex = buttons.indexWhere(
      (button) => button.position == sourcePosition,
    );
    final targetIndex = buttons.indexWhere(
      (button) => button.position == targetPosition,
    );
    if (sourceIndex < 0 || targetIndex < 0) return;

    final source = buttons[sourceIndex];
    final target = buttons[targetIndex];
    buttons[sourceIndex] = _moveButtonToPosition(target, sourcePosition);
    buttons[targetIndex] = _moveButtonToPosition(source, targetPosition);
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

  void _recordShortcutUsage(String key, String label) {
    unawaited(shortcutUsage.record(key, label).catchError((Object _) {}));
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
    final builtIns = await templates.loadAll();
    final template = builtIns
        .where((item) => item.id == activeProfile.id)
        .firstOrNull;
    await updateButton(
      template?.buttons[position] ?? ButtonConfig.empty(position),
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
    hid.activeHost.removeListener(_handleActiveHostChanged);
    hid.connectionStatus.removeListener(_handleActiveHostChanged);
    companion.activeHost.removeListener(_handleCompanionHostChanged);
    companion.manifest.removeListener(_handleCompanionManifestChanged);
    companion.syncStatus.removeListener(_handleCompanionManifestChanged);
    companion.errorMessage.removeListener(_handleCompanionManifestChanged);
    powerBrightnessService.isPluggedIn.removeListener(_handlePowerChanged);
    hid.dispose();
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
