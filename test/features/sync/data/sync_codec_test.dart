import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/sync/data/sync_codec.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';

void main() {
  late SyncCodec codec;
  late Uint8List key;
  final plaintext = Uint8List.fromList(
    utf8.encode('{"senderNodeId":"a","senderHlc":"1","data":{}}'),
  );

  setUp(() async {
    codec = SyncCodec();
    key = await SyncCodec.deriveKey('a-shared-sync-code-16chars');
  });

  group('deriveKey', () {
    test('produces a 32-byte key', () {
      expect(key.length, 32);
    });

    test('is deterministic for the same secret', () async {
      final again = await SyncCodec.deriveKey('a-shared-sync-code-16chars');
      expect(again, key);
    });

    test('different secrets yield unrelated keys', () async {
      final other = await SyncCodec.deriveKey('a-different-code-16chars!!');
      expect(other, isNot(equals(key)));
    });
  });

  group('seal / open round-trip', () {
    test('opens what it sealed on the export endpoint', () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpointTag: SyncCodec.endpointExport,
      );
      // Frame is nonce(12) ‖ ciphertext ‖ mac(16).
      expect(frame.length, plaintext.length + SyncCodec.frameOverhead);
      final opened = await codec.open(
        frame,
        key,
        endpointTag: SyncCodec.endpointExport,
      );
      expect(opened, plaintext);
    });

    test('round-trips the import endpoint with a challenge', () async {
      final challenge = Uint8List.fromList(List.generate(16, (i) => i));
      final frame = await codec.seal(
        plaintext,
        key,
        endpointTag: SyncCodec.endpointImport,
        challenge: challenge,
      );
      final opened = await codec.open(
        frame,
        key,
        endpointTag: SyncCodec.endpointImport,
        challenge: challenge,
      );
      expect(opened, plaintext);
    });
  });

  group('fail-closed', () {
    test('a tampered ciphertext byte throws CryptoException', () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpointTag: SyncCodec.endpointExport,
      );
      // Flip a byte inside the ciphertext region.
      frame[SyncCodec.frameOverhead] ^= 0xFF;
      expect(
        () => codec.open(frame, key, endpointTag: SyncCodec.endpointExport),
        throwsA(isA<CryptoException>()),
      );
    });

    test('the wrong key throws CryptoException', () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpointTag: SyncCodec.endpointExport,
      );
      final wrongKey = await SyncCodec.deriveKey('some-other-code-16chars!!');
      expect(
        () =>
            codec.open(frame, wrongKey, endpointTag: SyncCodec.endpointExport),
        throwsA(isA<CryptoException>()),
      );
    });

    test('an export frame cannot be opened as import (endpoint AAD)', () async {
      final frame = await codec.seal(
        plaintext,
        key,
        endpointTag: SyncCodec.endpointExport,
      );
      expect(
        () => codec.open(frame, key, endpointTag: SyncCodec.endpointImport),
        throwsA(isA<CryptoException>()),
      );
    });

    test('a mismatched replay challenge throws CryptoException', () async {
      final challengeA = Uint8List.fromList(List.filled(16, 1));
      final challengeB = Uint8List.fromList(List.filled(16, 2));
      final frame = await codec.seal(
        plaintext,
        key,
        endpointTag: SyncCodec.endpointImport,
        challenge: challengeA,
      );
      expect(
        () => codec.open(
          frame,
          key,
          endpointTag: SyncCodec.endpointImport,
          challenge: challengeB,
        ),
        throwsA(isA<CryptoException>()),
      );
    });

    test('a too-short frame throws BackupFormatException', () async {
      final tooShort = Uint8List.fromList(List.filled(10, 0));
      expect(
        () => codec.open(tooShort, key, endpointTag: SyncCodec.endpointExport),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('a plaintext JSON body is rejected, never decoded', () async {
      final plaintextBody = Uint8List.fromList(
        utf8.encode('{"senderNodeId":"evil","data":{"items":[]}}'),
      );
      // Longer than the 28-byte overhead, so it reaches the AEAD, which
      // fails the tag check rather than returning attacker-controlled bytes.
      expect(
        () => codec.open(
          plaintextBody,
          key,
          endpointTag: SyncCodec.endpointImport,
        ),
        throwsA(isA<CryptoException>()),
      );
    });
  });
}
