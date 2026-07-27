import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peckish/features/ai/data/ai_config.dart';

/// Where the API key lives — tiny seam so tests don't need the platform
/// keystore channel.
abstract class KeyStore {
  Future<String?> read();
  Future<void> write(String? value);
}

/// The real thing: Android Keystore-backed on device, localStorage-backed on
/// web (the browser has nothing stronger for a BYOK key).
class SecureKeyStore implements KeyStore {
  const SecureKeyStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'ai_anthropic_key';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? value) => value == null
      ? _storage.delete(key: _key)
      : _storage.write(key: _key, value: value);
}

/// Persists [AiConfig]: the key in [KeyStore], everything else in prefs.
/// The shipped default is [AiBackend.none] — configuring is the opt-in.
class AiConfigRepository {
  AiConfigRepository(this._prefs, this._keys);

  final SharedPreferences _prefs;
  final KeyStore _keys;

  static const _backendKey = 'ai_backend';
  static const _baseUrlKey = 'ai_base_url';
  static const _modelKey = 'ai_model';

  Future<AiConfig> load() async {
    final backend = AiBackend.values.asNameMap()[_prefs.getString(_backendKey)] ??
        AiBackend.none;
    return AiConfig(
      backend: backend,
      anthropicKey:
          backend == AiBackend.anthropic ? await _keys.read() : null,
      baseUrl: _prefs.getString(_baseUrlKey),
      model: _prefs.getString(_modelKey),
    );
  }

  Future<void> save(AiConfig config) async {
    await _prefs.setString(_backendKey, config.backend.name);
    await _setOrRemove(_baseUrlKey, config.baseUrl);
    await _setOrRemove(_modelKey, config.model);
    // Off means off: no residue key in secure storage.
    await _keys.write(
        config.backend == AiBackend.anthropic ? config.anthropicKey : null);
  }

  Future<void> _setOrRemove(String key, String? value) =>
      value == null || value.isEmpty
          ? _prefs.remove(key)
          : _prefs.setString(key, value);
}
