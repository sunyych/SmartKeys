import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;
import 'package:shared_preferences/shared_preferences.dart';

/// These targets are local Desktop authority, never mobile protocol fields.
enum InstalledLaunchKind {
  windowsAppId,
  windowsShortcut,
  windowsExecutable,
  macBundle,
  linuxDesktopEntry,
  linuxExecutable,
}

String installedApplicationId(InstalledLaunchKind kind, String identity) =>
    'installed.${sha256.convert(utf8.encode('${kind.name}\u0000$identity')).toString().substring(0, 32)}';

class InstalledLaunchTarget {
  const InstalledLaunchTarget({
    required this.id,
    required this.name,
    required this.kind,
    required this.identity,
    required this.locator,
    this.executablePath,
    this.startupWMClass,
    this.iconKey,
    this.available = true,
    this.manual = false,
  });

  factory InstalledLaunchTarget.discovered({
    required String name,
    required InstalledLaunchKind kind,
    required String identity,
    required String locator,
    String? executablePath,
    String? startupWMClass,
    String? iconKey,
    bool manual = false,
  }) => InstalledLaunchTarget(
    id: installedApplicationId(kind, identity),
    name: name,
    kind: kind,
    identity: identity,
    locator: locator,
    executablePath: executablePath,
    startupWMClass: startupWMClass,
    iconKey: iconKey,
    manual: manual,
  );

  final String id, name, identity, locator;
  final InstalledLaunchKind kind;
  final String? executablePath, startupWMClass, iconKey;
  final bool available, manual;

  InstalledLaunchTarget copyWith({bool? available}) => InstalledLaunchTarget(
    id: id,
    name: name,
    kind: kind,
    identity: identity,
    locator: locator,
    executablePath: executablePath,
    startupWMClass: startupWMClass,
    iconKey: iconKey,
    available: available ?? this.available,
    manual: manual,
  );

  /// Persistence is Desktop-only. Never embed this map in a synced manifest.
  Map<String, Object?> toLocalJson() => {
    'id': id,
    'name': name,
    'kind': kind.name,
    'identity': identity,
    'locator': locator,
    'executablePath': executablePath,
    'startupWMClass': startupWMClass,
    'iconKey': iconKey,
    'manual': manual,
  };

  factory InstalledLaunchTarget.fromLocalJson(Object? value) {
    const keys = {
      'id',
      'name',
      'kind',
      'identity',
      'locator',
      'executablePath',
      'startupWMClass',
      'iconKey',
      'manual',
    };
    if (value is! Map ||
        value.length != keys.length ||
        value.keys.any((key) => !keys.contains(key)) ||
        value['manual'] != true) {
      throw const FormatException('Invalid local installed application');
    }
    String text(String key) {
      final field = value[key];
      if (field is! String) {
        throw const FormatException('Invalid local application field');
      }
      return field;
    }

    String? optional(String key) {
      final field = value[key];
      if (field != null && field is! String) {
        throw const FormatException('Invalid local application field');
      }
      return field as String?;
    }

    final kind = InstalledLaunchKind.values.where(
      (kind) => kind.name == value['kind'],
    );
    if (kind.length != 1) {
      throw const FormatException('Invalid local application kind');
    }
    final target = InstalledLaunchTarget(
      id: text('id'),
      name: text('name'),
      kind: kind.single,
      identity: text('identity'),
      locator: text('locator'),
      executablePath: optional('executablePath'),
      startupWMClass: optional('startupWMClass'),
      iconKey: optional('iconKey'),
      manual: true,
      available: false,
    );
    validateInstalledTarget(target);
    return target;
  }
}

void validateInstalledTarget(InstalledLaunchTarget target) {
  bool validText(String value, int limit) =>
      value.isNotEmpty &&
      value.length <= limit &&
      !value.codeUnits.any((unit) => unit < 32 || unit == 127);
  if (target.id != installedApplicationId(target.kind, target.identity) ||
      !validText(target.name, 256) ||
      !validText(target.identity, 4096) ||
      !validText(target.locator, 4096) ||
      [
        target.executablePath,
        target.startupWMClass,
        target.iconKey,
      ].any((value) => value != null && !validText(value, 4096))) {
    throw const FormatException('Invalid registered application target');
  }
  switch (target.kind) {
    case InstalledLaunchKind.windowsAppId:
      if (target.manual) {
        throw const FormatException('App IDs must come from Windows discovery');
      }
    case InstalledLaunchKind.windowsShortcut:
      if (!paths.windows.isAbsolute(target.locator) ||
          !target.locator.toLowerCase().endsWith('.lnk')) {
        throw const FormatException('Expected an absolute Windows shortcut');
      }
    case InstalledLaunchKind.windowsExecutable:
      if (!paths.windows.isAbsolute(target.locator) ||
          !target.locator.toLowerCase().endsWith('.exe')) {
        throw const FormatException('Expected an absolute Windows executable');
      }
    case InstalledLaunchKind.macBundle:
      if (!paths.posix.isAbsolute(target.locator) ||
          !target.locator.endsWith('.app')) {
        throw const FormatException('Expected an absolute application bundle');
      }
    case InstalledLaunchKind.linuxDesktopEntry:
      if (!paths.posix.isAbsolute(target.locator) ||
          !target.locator.endsWith('.desktop')) {
        throw const FormatException('Expected an absolute desktop entry');
      }
    case InstalledLaunchKind.linuxExecutable:
      if (!paths.posix.isAbsolute(target.locator)) {
        throw const FormatException(
          'Expected an absolute application executable',
        );
      }
  }
}

Future<bool> installedTargetExists(InstalledLaunchTarget target) async {
  validateInstalledTarget(target);
  if (target.kind == InstalledLaunchKind.windowsAppId) return target.available;
  if (target.kind == InstalledLaunchKind.macBundle) {
    return await Directory(target.locator).exists() &&
        await File(
          paths.join(target.locator, 'Contents', 'Info.plist'),
        ).exists();
  }
  final file = File(target.locator);
  if (!await file.exists()) return false;
  if (target.kind == InstalledLaunchKind.linuxExecutable) {
    return (await file.stat()).mode & 0x49 != 0;
  }
  return true;
}

abstract interface class InstalledRegistryStore {
  Future<List<InstalledLaunchTarget>> load();
  Future<void> save(List<InstalledLaunchTarget> targets);
}

class SharedPreferencesInstalledRegistryStore
    implements InstalledRegistryStore {
  SharedPreferencesInstalledRegistryStore({SharedPreferencesAsync? preferences})
    : preferences = preferences ?? SharedPreferencesAsync();
  final SharedPreferencesAsync preferences;
  static const storageKey = 'lumiakeys.desktop.installed_manual.v1';
  @override
  Future<List<InstalledLaunchTarget>> load() async {
    final raw = await preferences.getString(storageKey);
    if (raw == null) return [];
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const FormatException('Local application registry is too large');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map ||
        decoded.length != 2 ||
        decoded['schemaVersion'] != 1 ||
        decoded['targets'] is! List ||
        (decoded['targets'] as List).length > 1000) {
      throw const FormatException('Invalid local application registry');
    }
    return (decoded['targets'] as List)
        .map(InstalledLaunchTarget.fromLocalJson)
        .toList();
  }

  @override
  Future<void> save(List<InstalledLaunchTarget> targets) async {
    if (targets.length > 1000) {
      throw const FormatException('Too many local applications');
    }
    final ids = <String>{};
    for (final target in targets) {
      validateInstalledTarget(target);
      if (!target.manual || !ids.add(target.id)) {
        throw const FormatException('Invalid duplicate manual application');
      }
    }
    final raw = jsonEncode({
      'schemaVersion': 1,
      'targets': targets.map((target) => target.toLocalJson()).toList(),
    });
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const FormatException('Local application registry is too large');
    }
    await preferences.setString(storageKey, raw);
  }
}

class MemoryInstalledRegistryStore implements InstalledRegistryStore {
  List<InstalledLaunchTarget> value = [];
  bool failRead = false, failSave = false;
  @override
  Future<List<InstalledLaunchTarget>> load() async {
    if (failRead) throw StateError('Local registry unavailable');
    return List.of(value);
  }

  @override
  Future<void> save(List<InstalledLaunchTarget> targets) async {
    if (failSave) throw StateError('Local registry unavailable');
    value = List.of(targets);
  }
}

class InstalledAppRegistry {
  InstalledAppRegistry({
    Future<List<InstalledLaunchTarget>> Function()? discover,
    InstalledRegistryStore? store,
    Future<bool> Function(InstalledLaunchTarget)? validate,
    DateTime Function()? clock,
    this.cacheDuration = const Duration(seconds: 60),
    this.validationTimeout = const Duration(seconds: 2),
    this.scanTimeout = const Duration(seconds: 20),
  }) : _discover = discover ?? _empty,
       store = store ?? MemoryInstalledRegistryStore(),
       _validate = validate ?? installedTargetExists,
       _clock = clock ?? DateTime.now {
    if (validationTimeout <= Duration.zero ||
        validationTimeout > const Duration(seconds: 2) ||
        scanTimeout <= Duration.zero ||
        scanTimeout > const Duration(seconds: 20)) {
      throw ArgumentError(
        'Installed validation/scans exceed their bounded budget',
      );
    }
    if (cacheDuration < const Duration(seconds: 60)) {
      throw ArgumentError(
        'Installed scans require at least sixty seconds of caching',
      );
    }
  }
  static Future<List<InstalledLaunchTarget>> _empty() async => [];
  final Future<List<InstalledLaunchTarget>> Function() _discover;
  final InstalledRegistryStore store;
  final Future<bool> Function(InstalledLaunchTarget) _validate;
  final DateTime Function() _clock;
  final Duration cacheDuration, validationTimeout, scanTimeout;
  int _loadGeneration = 0, _scanGeneration = 0;
  Map<String, InstalledLaunchTarget> _manual = {}, _scanned = {};
  Future<void>? _initializing, _refreshing;
  Future<void> _manualWrites = Future.value();
  bool _loaded = false;
  DateTime? _lastScan;
  String? error;

  List<InstalledLaunchTarget> get entries {
    final values = {..._scanned, ..._manual}.values.toList();
    values.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return List.unmodifiable(values);
  }

  InstalledLaunchTarget? resolve(String id) {
    final target = _manual[id] ?? _scanned[id];
    return target?.available == true ? target : null;
  }

  Future<bool> _available(InstalledLaunchTarget target) async {
    try {
      return await _validate(target).timeout(validationTimeout);
    } catch (_) {
      return false;
    }
  }

  Future<List<InstalledLaunchTarget>> _validated(
    List<InstalledLaunchTarget> targets, {
    bool Function()? active,
  }) async {
    final result = <InstalledLaunchTarget>[];
    for (var offset = 0; offset < targets.length; offset += 32) {
      if (active != null && !active()) {
        throw StateError('Application scan was superseded');
      }
      final batch = targets.skip(offset).take(32);
      result.addAll(
        await Future.wait(
          batch.map(
            (target) async =>
                target.copyWith(available: await _available(target)),
          ),
        ),
      );
    }
    return result;
  }

  Future<void> initialize() async {
    if (_loaded) return;
    if (_initializing != null) return _initializing!;
    final generation = ++_loadGeneration;
    final operation = _load(generation).timeout(scanTimeout);
    _initializing = operation;
    try {
      await operation;
    } catch (_) {
      if (_loadGeneration == generation) _loadGeneration++;
      error =
          'Saved applications could not be read. Saved launchpad slots are unchanged.';
      rethrow;
    } finally {
      if (identical(_initializing, operation)) _initializing = null;
    }
  }

  Future<void> _load(int generation) async {
    final saved = await store.load();
    if (saved.length > 1000) {
      throw const FormatException('Too many local applications');
    }
    final ids = <String>{};
    for (final target in saved) {
      validateInstalledTarget(target);
      if (!target.manual || !ids.add(target.id)) {
        throw const FormatException('Invalid duplicate manual application');
      }
    }
    final validated = await _validated(
      saved,
      active: () => generation == _loadGeneration,
    );
    if (generation != _loadGeneration) return;
    _manual = {for (final target in validated) target.id: target};
    _loaded = true;
    error = null;
  }

  Future<void> refresh({bool force = false}) async {
    await initialize();
    if (_refreshing != null) return _refreshing!;
    if (!force &&
        _lastScan != null &&
        _clock().difference(_lastScan!) >= Duration.zero &&
        _clock().difference(_lastScan!) < cacheDuration) {
      return;
    }
    final operation = _scan();
    _refreshing = operation;
    try {
      await operation;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _scan() async {
    final generation = ++_scanGeneration;
    try {
      await _stageScan(generation).timeout(scanTimeout);
    } catch (_) {
      if (_scanGeneration == generation) _scanGeneration++;
      _scanned = {
        for (final target in _scanned.values)
          target.id: target.copyWith(available: false),
      };
      error =
          'Installed applications could not be refreshed. Existing launchpad slots are preserved.';
      rethrow;
    }
  }

  Future<void> _stageScan(int generation) async {
    final found = await _discover();
    if (generation != _scanGeneration) return;
    if (found.length > 2000) {
      throw const FormatException('Too many installed applications');
    }
    final ids = <String>{};
    for (final target in found) {
      validateInstalledTarget(target);
      if (target.manual || !ids.add(target.id)) {
        throw const FormatException('Duplicate installed application identity');
      }
    }
    final checked = await _validated(
      found,
      active: () => generation == _scanGeneration,
    );
    final manualSnapshot = Map<String, InstalledLaunchTarget>.of(_manual);
    final manualChecked = await _validated(
      manualSnapshot.values.toList(),
      active: () => generation == _scanGeneration,
    );
    if (generation != _scanGeneration) return;
    // No inventory tombstone accumulation: selected unavailable labels are
    // retained by the controller's twelve-slot manifest, not this OS inventory.
    _scanned = {for (final target in checked) target.id: target};
    for (final target in manualChecked) {
      if (identical(_manual[target.id], manualSnapshot[target.id])) {
        _manual[target.id] = target;
      }
    }
    _lastScan = _clock();
    error = null;
  }

  Future<void> addManual(InstalledLaunchTarget target) {
    final operation = _manualWrites.then((_) async {
      await initialize();
      if (!_loaded || !target.manual) {
        throw const FormatException('Manual targets must be chosen locally');
      }
      validateInstalledTarget(target);
      if (!await _available(target)) {
        throw const FormatException('The selected application is unavailable');
      }
      final next = {..._manual, target.id: target.copyWith(available: true)};
      if (next.length > 1000) {
        throw const FormatException('Too many local applications');
      }
      await store.save(next.values.toList());
      _manual = next;
    });
    _manualWrites = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> removeManual(String id) {
    final operation = _manualWrites.then((_) async {
      await initialize();
      final next = Map<String, InstalledLaunchTarget>.of(_manual)..remove(id);
      await store.save(next.values.toList());
      _manual = next;
    });
    _manualWrites = operation.catchError((Object _) {});
    return operation;
  }
}
