import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/config_repository.dart';
import '../data/private_image_store.dart';
import '../data/profile_template_repository.dart';
import '../models/config.dart';
import '../services/hid_service.dart';
import '../services/orientation_service.dart';
import '../services/power_brightness_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.repository,
    required this.templates,
    required this.hid,
    required this.orientationService,
    required this.imageStore,
    required this.powerBrightnessService,
  }) {
    hid.activeHost.addListener(_handleActiveHostChanged);
    powerBrightnessService.isPluggedIn.addListener(_handlePowerChanged);
  }

  final ConfigRepository repository;
  final ProfileTemplateRepository templates;
  final HidService hid;
  final OrientationService orientationService;
  final PrivateImageStore imageStore;
  final PowerBrightnessService powerBrightnessService;

  AppConfig? _config;
  bool _isLoading = true;
  Object? _error;
  bool? _lastLandscape;
  int _inputEpoch = 0;
  final Set<int> _pressedPositions = {};
  final Map<int, HidAction> _pressedButtonActions = {};
  HidAction? _pressedWheelCenterAction;
  ButtonConfig? _buttonClipboard;
  int _profileIdSequence = 0;

  bool get isLoading => _isLoading;
  Object? get error => _error;
  AppConfig get config => _config!;
  ProfileConfig get activeProfile => config.activeProfile;
  Set<int> get pressedPositions => Set.unmodifiable(_pressedPositions);
  int get inputEpoch => _inputEpoch;
  bool get hasButtonClipboard => _buttonClipboard != null;
  bool get canAddProfile => config.profiles.length < freeProfileLimit;
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
      await orientationService.apply(config.preferences.orientationMode);
      await powerBrightnessService.initialize();
      await _applyBrightnessForCurrentPowerState();
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
      await hid.sendStep(_resolveShortcutAction(action));
    }
  }

  Future<void> pressWheelCenter() async {
    final action = activeProfile.wheel.center;
    if (action.type != ActionType.none) {
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
      hid.sendPress(
        HidAction(type: ActionType.mouseMove, value: '$x,$y'),
      ),
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
  }) async {
    _config = config.copyWith(
      preferences: config.preferences.copyWith(
        chargingBrightnessMode: mode,
        chargingBrightness: brightness,
      ),
    );
    notifyListeners();
    await Future.wait([
      repository.save(config),
      _applyBrightnessForCurrentPowerState(),
    ]);
  }

  Future<void> handleAppResumed() async {
    await powerBrightnessService.refreshPowerState();
    await _applyBrightnessForCurrentPowerState();
  }

  void _handlePowerChanged() {
    notifyListeners();
    unawaited(_applyBrightnessForCurrentPowerState());
  }

  Future<void> _applyBrightnessForCurrentPowerState() {
    final preferences = config.preferences;
    final fixedWhileCharging =
        powerBrightnessService.isPluggedIn.value == true &&
        preferences.chargingBrightnessMode == ChargingBrightnessMode.fixed;
    return powerBrightnessService.setAppBrightness(
      fixedWhileCharging ? preferences.chargingBrightness : null,
    );
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
    await imageStore.cleanupUnreferenced(config);
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
    powerBrightnessService.isPluggedIn.removeListener(_handlePowerChanged);
    hid.dispose();
    powerBrightnessService.dispose();
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
