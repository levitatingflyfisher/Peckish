import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the household sync secret lives. The secret IS the pairing: every
/// device that knows it derives the same frame key, and nothing else can
/// open (or forge) a single frame. Tiny seam so tests skip the platform
/// keystore channel.
abstract class SyncSecretStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureSyncSecretStore implements SyncSecretStore {
  const SecureSyncSecretStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _key = 'sync_secret';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// In-memory store for tests and for the loopback harness.
class InMemorySyncSecretStore implements SyncSecretStore {
  String? _value;

  /// What the last write stored — a test-visible receipt.
  String? get lastWritten => _value;

  @override
  Future<String?> read() async => _value;
  @override
  Future<void> write(String value) async => _value = value;
}

/// Sync secrets must not be trivially brute-forceable — the frame key is
/// HKDF(secret) with no other input.
const int kMinSyncSecretLength = 16;
