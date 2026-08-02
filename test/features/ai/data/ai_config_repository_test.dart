import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/ai_config_repository.dart';
import 'package:peckish/features/ai/data/stove_secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemoryKeyStore implements KeyStore {
  String? _key;
  @override
  Future<String?> read() async => _key;
  @override
  Future<void> write(String? value) async => _key = value;
}

// The secrets (API key, household phrase) live in secure storage,
// everything else in prefs; the shipped default is backend none — no key,
// no endpoint, no tile, no network.
void main() {
  test('the shipped default is off', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = AiConfigRepository(await SharedPreferences.getInstance(),
        _InMemoryKeyStore(), InMemoryStoveSecretStore());
    final config = await repo.load();
    expect(config.backend, AiBackend.none);
    expect(config.configured, isFalse);
  });

  test('saving and reloading round-trips both backends', () async {
    SharedPreferences.setMockInitialValues({});
    final keys = _InMemoryKeyStore();
    final repo = AiConfigRepository(await SharedPreferences.getInstance(),
        keys, InMemoryStoveSecretStore());

    await repo.save(const AiConfig(
      backend: AiBackend.anthropic,
      anthropicKey: 'sk-ant-x',
      model: 'claude-sonnet-4-6',
    ));
    var loaded = await repo.load();
    expect(loaded.backend, AiBackend.anthropic);
    expect(loaded.anthropicKey, 'sk-ant-x');
    expect(loaded.configured, isTrue);
    expect(await keys.read(), 'sk-ant-x',
        reason: 'the key belongs in secure storage, not prefs');

    await repo.save(const AiConfig(
      backend: AiBackend.openaiCompat,
      baseUrl: 'http://localhost:8080',
      model: 'qwen2.5:1.5b',
    ));
    loaded = await repo.load();
    expect(loaded.backend, AiBackend.openaiCompat);
    expect(loaded.baseUrl, 'http://localhost:8080');
    expect(loaded.configured, isTrue);
  });

  test('turning it off clears the stored key', () async {
    SharedPreferences.setMockInitialValues({});
    final keys = _InMemoryKeyStore();
    final repo = AiConfigRepository(await SharedPreferences.getInstance(),
        keys, InMemoryStoveSecretStore());
    await repo.save(const AiConfig(
        backend: AiBackend.anthropic, anthropicKey: 'sk-ant-x'));
    await repo.save(const AiConfig(backend: AiBackend.none));
    expect((await repo.load()).configured, isFalse);
    expect(await keys.read(), isNull,
        reason: 'off means off — no residue key in secure storage');
  });

  group('the stove backend', () {
    const phrase =
        'abandon abandon abandon abandon abandon abandon '
        'abandon abandon abandon abandon abandon about';

    test('round-trips host + port in prefs, the phrase in secure storage',
        () async {
      SharedPreferences.setMockInitialValues({});
      final stoveSecrets = InMemoryStoveSecretStore();
      final repo = AiConfigRepository(await SharedPreferences.getInstance(),
          _InMemoryKeyStore(), stoveSecrets);

      await repo.save(const AiConfig(
        backend: AiBackend.stove,
        stoveHost: '192.168.1.20',
        stovePort: 4700,
        stovePhrase: phrase,
      ));
      final loaded = await repo.load();
      expect(loaded.backend, AiBackend.stove);
      expect(loaded.stoveHost, '192.168.1.20');
      expect(loaded.stovePort, 4700);
      expect(loaded.stovePhrase, phrase);
      expect(loaded.configured, isTrue);
      expect(await stoveSecrets.read(), phrase,
          reason: 'the household phrase belongs in secure storage, '
              'never prefs');
      final prefs = await SharedPreferences.getInstance();
      final residue = prefs
          .getKeys()
          .map((k) => prefs.get(k).toString())
          .where((v) => v.contains('abandon'));
      expect(residue, isEmpty, reason: 'no phrase residue anywhere in prefs');
    });

    test('an absent port loads as null and configured needs host + phrase',
        () async {
      SharedPreferences.setMockInitialValues({});
      final repo = AiConfigRepository(await SharedPreferences.getInstance(),
          _InMemoryKeyStore(), InMemoryStoveSecretStore());

      await repo.save(const AiConfig(
          backend: AiBackend.stove, stoveHost: 'stove.local'));
      final loaded = await repo.load();
      expect(loaded.stovePort, isNull,
          reason: 'the default port is applied at ask time, not stored');
      expect(loaded.configured, isFalse,
          reason: 'a stove without its household phrase cannot be asked');
    });

    test('switching away clears the stored phrase', () async {
      SharedPreferences.setMockInitialValues({});
      final stoveSecrets = InMemoryStoveSecretStore();
      final repo = AiConfigRepository(await SharedPreferences.getInstance(),
          _InMemoryKeyStore(), stoveSecrets);
      await repo.save(const AiConfig(
        backend: AiBackend.stove,
        stoveHost: 'stove.local',
        stovePhrase: phrase,
      ));
      await repo.save(const AiConfig(backend: AiBackend.none));
      expect(await stoveSecrets.read(), isNull,
          reason: 'off means off — no residue phrase in secure storage');
    });
  });
}
