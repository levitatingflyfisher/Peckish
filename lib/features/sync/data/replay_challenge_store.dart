import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Tracks the single-use replay challenges the LAN-sync server issues over
/// `/sync/status` and consumes on `/sync/import`.
///
/// This is the piece that earns the name "replay separation": a mutating
/// import must echo a challenge the server issued and has not yet seen. A
/// replayed import frame carries an already-consumed (or expired) challenge,
/// so it is rejected before any DB mutation — genuine wire-replay protection,
/// not the theatre of a client-echoed nonce folded into a static key.
///
/// It is NOT forward secrecy: the frame key is still the static
/// HKDF(sync-secret) key (sanctuary exports no ECDH).
///
/// Pure Dart (no `dart:io`) so it stays web-clean by construction, though only
/// the native server ever constructs one.
class ReplayChallengeStore {
  /// How long an issued challenge stays valid before it is discarded.
  final Duration ttl;

  /// Upper bound on outstanding challenges — a flood of `/sync/status` probes
  /// cannot grow this map without bound.
  final int maxOutstanding;

  final Random _random;
  final DateTime Function() _clock;
  final Map<String, DateTime> _issued = {};

  ReplayChallengeStore({
    this.ttl = const Duration(minutes: 5),
    this.maxOutstanding = 256,
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? DateTime.now;

  /// Issues a fresh 16-byte challenge, records it, and returns it base64-encoded
  /// (the token carried in the status response and echoed in the import header).
  String issue() {
    _evictExpired();
    if (_issued.length >= maxOutstanding) {
      // Bound memory: drop the oldest outstanding challenge.
      final oldest = _issued.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      _issued.remove(oldest.key);
    }
    final bytes = Uint8List(16);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    final token = base64.encode(bytes);
    _issued[token] = _clock();
    return token;
  }

  /// Consumes [token] if it is outstanding and unexpired, returning the raw
  /// 16 challenge bytes so the caller can bind them into the frame AAD.
  ///
  /// Returns null on an unknown, expired, malformed, or already-used token —
  /// the fail-closed / single-use paths. A consumed token can never be
  /// consumed again (the replay defence).
  Uint8List? consume(String token) {
    _evictExpired();
    final issuedAt = _issued.remove(token);
    if (issuedAt == null) return null; // unknown or already used
    if (_clock().difference(issuedAt) > ttl) return null; // expired
    try {
      final bytes = base64.decode(token);
      if (bytes.length != 16) return null;
      return Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  /// Number of currently-outstanding (unexpired) challenges — for tests.
  int get outstandingCount {
    _evictExpired();
    return _issued.length;
  }

  void _evictExpired() {
    final now = _clock();
    _issued.removeWhere((_, issuedAt) => now.difference(issuedAt) > ttl);
  }
}
