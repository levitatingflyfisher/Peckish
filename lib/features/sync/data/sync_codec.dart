import 'dart:convert';
import 'dart:typed_data';

import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';

/// Seals and opens the binary AEAD frames exchanged over LAN sync.
///
/// This file is deliberately free of `dart:io` — it is imported by the sync
/// client, which is compiled on web. All crypto comes from
/// `sanctuary_auth_core` (pure-Dart ChaCha20-Poly1305 + HKDF); nothing is
/// hand-rolled here.
///
/// Wire frame (`application/octet-stream`):
///
/// ```text
///   nonce(12) ‖ ciphertext(plaintext.length) ‖ mac(16)
/// ```
///
/// The 32-byte key is HKDF-derived from the existing shared sync secret.
/// The AAD binds each frame to the protocol, its endpoint, the protocol
/// version, and — for the mutating endpoint — the single-use replay
/// challenge, so a frame can never be replayed across endpoints or protocol
/// versions.
class SyncCodec {
  /// HKDF `info` label for deriving the LAN-sync frame key. A distinct label
  /// keeps this key cryptographically separated from every other sanctuary
  /// purpose sharing the same input bytes.
  static const String keyDomain = 'peckish.lan.v1';

  /// Wire-protocol version. Negotiated in cleartext over `/sync/status` and
  /// bound into the AAD; bump on any wire-format change so peers fail closed.
  static const int protocolVersion = 1;

  /// AAD namespace prefix — binds every frame to the Peckish LAN protocol.
  static const String _aadPrefix = 'peckish-lan/v1';

  /// Endpoint tag for the read-only export response body.
  static const String endpointExport = 'export';

  /// Endpoint tag for the state-mutating import request body.
  static const String endpointImport = 'import';

  static const int _nonceLen = 12;
  static const int _macLen = 16;

  /// Fixed per-frame AEAD overhead: 12-byte nonce + 16-byte Poly1305 tag.
  static const int frameOverhead = _nonceLen + _macLen; // 28 bytes

  final EnvelopeCipher _cipher;

  SyncCodec({EnvelopeCipher? cipher}) : _cipher = cipher ?? EnvelopeCipher();

  /// Derives the 32-byte frame key from the shared sync [secret].
  ///
  /// Routes through `KeyDerivation.deriveKey` (HKDF-SHA256) rather than
  /// hand-rolling a KDF. The same [secret] on two paired devices yields the
  /// same key; a different secret yields an unrelated key.
  static Future<Uint8List> deriveKey(String secret) => KeyDerivation.deriveKey(
        Uint8List.fromList(utf8.encode(secret)),
        domain: keyDomain,
      );

  /// Builds the AAD bytes for a frame on [endpointTag].
  ///
  /// [challenge] is the single-use replay nonce issued by `/sync/status`;
  /// pass null for endpoints (export) that carry no challenge.
  static Uint8List additionalData(String endpointTag, {Uint8List? challenge}) {
    final label = StringBuffer()
      ..write(_aadPrefix)
      ..write('|')
      ..write(endpointTag)
      ..write('|')
      ..write(protocolVersion);
    if (challenge != null) {
      label
        ..write('|')
        ..write(base64.encode(challenge));
    }
    return Uint8List.fromList(utf8.encode(label.toString()));
  }

  /// Seals [plaintext] into a binary frame under [key].
  ///
  /// [key] must be exactly 32 bytes (see [deriveKey]).
  Future<Uint8List> seal(
    Uint8List plaintext,
    Uint8List key, {
    required String endpointTag,
    Uint8List? challenge,
  }) async {
    final env = await _cipher.encrypt(
      plaintext,
      key,
      additionalData: additionalData(endpointTag, challenge: challenge),
    );
    final out = Uint8List(
      env.nonce.length + env.ciphertext.length + env.mac.length,
    );
    out.setAll(0, env.nonce);
    out.setAll(env.nonce.length, env.ciphertext);
    out.setAll(env.nonce.length + env.ciphertext.length, env.mac);
    return out;
  }

  /// Opens a binary frame produced by [seal].
  ///
  /// Throws [BackupFormatException] on a structurally-invalid frame (too short
  /// to hold a nonce + tag — e.g. a plaintext body), and [CryptoException]
  /// on a wrong key, tampered bytes, or an AAD mismatch (wrong endpoint,
  /// protocol version, or replay challenge). Never returns partial plaintext.
  Future<Uint8List> open(
    Uint8List frame,
    Uint8List key, {
    required String endpointTag,
    Uint8List? challenge,
  }) async {
    if (frame.length < frameOverhead) {
      throw BackupFormatException(
        'Sync frame too short: ${frame.length} bytes (minimum $frameOverhead).',
      );
    }
    final nonce = Uint8List.fromList(frame.sublist(0, _nonceLen));
    final mac = Uint8List.fromList(frame.sublist(frame.length - _macLen));
    final ciphertext = Uint8List.fromList(
      frame.sublist(_nonceLen, frame.length - _macLen),
    );
    final env = CipherEnvelope(nonce: nonce, ciphertext: ciphertext, mac: mac);
    return _cipher.decrypt(
      env,
      key,
      additionalData: additionalData(endpointTag, challenge: challenge),
    );
  }
}
