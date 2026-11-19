import 'package:shared_preferences/shared_preferences.dart';

abstract interface class DesktopPairingAddressStore {
  Future<String?> load();
  Future<void> save(String address);
}

class SharedPreferencesDesktopPairingAddressStore
    implements DesktopPairingAddressStore {
  SharedPreferencesDesktopPairingAddressStore({
    SharedPreferencesAsync? preferences,
  }) : _providedPreferences = preferences;

  static const _storageKey = 'lumiakeys.desktop.pairing_address.v1';
  final SharedPreferencesAsync? _providedPreferences;
  late final SharedPreferencesAsync _preferences =
      _providedPreferences ?? SharedPreferencesAsync();
  Future<void> _writeTail = Future<void>.value();

  @override
  Future<String?> load() async {
    await _writeTail;
    return _preferences.getString(_storageKey);
  }

  @override
  Future<void> save(String address) {
    final write = _writeTail.then(
      (_) => _preferences.setString(_storageKey, address),
    );
    _writeTail = write.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}

class MemoryDesktopPairingAddressStore implements DesktopPairingAddressStore {
  String? _address;

  @override
  Future<String?> load() async => _address;

  @override
  Future<void> save(String address) async => _address = address;
}
