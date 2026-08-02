import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the household phrase for the stove backend lives (the
/// sync_secret_store pattern). The secret IS the pairing: both ends derive
/// the same stove key from the same phrase, and nothing else can open (or
/// forge) a frame. Tiny seam so tests skip the platform keystore channel.
///
/// `write(null)` deletes — the KeyStore semantic, because "off means off"
/// must be expressible: leaving the stove backend clears the phrase.
abstract class StoveSecretStore {
  Future<String?> read();
  Future<void> write(String? value);
}

class SecureStoveSecretStore implements StoveSecretStore {
  const SecureStoveSecretStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'stove_phrase';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? value) => value == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: value);
}

/// In-memory store for tests.
class InMemoryStoveSecretStore implements StoveSecretStore {
  String? _value;

  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String? value) async => _value = value;
}
