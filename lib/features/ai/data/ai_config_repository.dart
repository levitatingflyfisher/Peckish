import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/stove_secret_store.dart';

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

/// Persists [AiConfig]: the secrets (API key, household phrase) in their
/// secure-storage seams, everything else in prefs. The shipped default is
/// [AiBackend.none] — configuring is the opt-in.
class AiConfigRepository {
  AiConfigRepository(this._prefs, this._keys, this._stoveSecrets);

  final SharedPreferences _prefs;
  final KeyStore _keys;
  final StoveSecretStore _stoveSecrets;

  static const _backendKey = 'ai_backend';
  static const _baseUrlKey = 'ai_base_url';
  static const _modelKey = 'ai_model';
  static const _stoveHostKey = 'ai_stove_host';
  static const _stovePortKey = 'ai_stove_port';

  Future<AiConfig> load() async {
    final backend =
        AiBackend.values.asNameMap()[_prefs.getString(_backendKey)] ??
            AiBackend.none;
    return AiConfig(
      backend: backend,
      anthropicKey: backend == AiBackend.anthropic ? await _keys.read() : null,
      baseUrl: _prefs.getString(_baseUrlKey),
      model: _prefs.getString(_modelKey),
      stoveHost: _prefs.getString(_stoveHostKey),
      stovePort: _prefs.getInt(_stovePortKey),
      stovePhrase:
          backend == AiBackend.stove ? await _stoveSecrets.read() : null,
    );
  }

  Future<void> save(AiConfig config) async {
    await _prefs.setString(_backendKey, config.backend.name);
    await _setOrRemove(_baseUrlKey, config.baseUrl);
    await _setOrRemove(_modelKey, config.model);
    await _setOrRemove(_stoveHostKey, config.stoveHost);
    final port = config.stovePort;
    if (port == null) {
      await _prefs.remove(_stovePortKey);
    } else {
      await _prefs.setInt(_stovePortKey, port);
    }
    // Off means off: no residue secret in secure storage — either seam.
    await _keys.write(
        config.backend == AiBackend.anthropic ? config.anthropicKey : null);
    await _stoveSecrets.write(config.backend == AiBackend.stove
        ? _emptyToNull(config.stovePhrase)
        : null);
  }

  static String? _emptyToNull(String? value) =>
      value == null || value.isEmpty ? null : value;

  Future<void> _setOrRemove(String key, String? value) =>
      value == null || value.isEmpty
          ? _prefs.remove(key)
          : _prefs.setString(key, value);
}
