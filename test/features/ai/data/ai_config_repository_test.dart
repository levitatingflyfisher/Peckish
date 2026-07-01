import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/ai_config_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _InMemoryKeyStore implements KeyStore {
  String? _key;
  @override
  Future<String?> read() async => _key;
  @override
  Future<void> write(String? value) async => _key = value;
}

// The key lives in secure storage, everything else in prefs; the shipped
// default is backend none — no key, no endpoint, no tile, no network.
void main() {
  test('the shipped default is off', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = AiConfigRepository(
        await SharedPreferences.getInstance(), _InMemoryKeyStore());
    final config = await repo.load();
    expect(config.backend, AiBackend.none);
    expect(config.configured, isFalse);
  });

  test('saving and reloading round-trips both backends', () async {
    SharedPreferences.setMockInitialValues({});
    final keys = _InMemoryKeyStore();
    final repo =
        AiConfigRepository(await SharedPreferences.getInstance(), keys);

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
    final repo =
        AiConfigRepository(await SharedPreferences.getInstance(), keys);
    await repo.save(const AiConfig(
        backend: AiBackend.anthropic, anthropicKey: 'sk-ant-x'));
    await repo.save(const AiConfig(backend: AiBackend.none));
    expect((await repo.load()).configured, isFalse);
    expect(await keys.read(), isNull,
        reason: 'off means off — no residue key in secure storage');
  });
}
