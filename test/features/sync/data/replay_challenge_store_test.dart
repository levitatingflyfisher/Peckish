import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/sync/data/replay_challenge_store.dart';

void main() {
  group('ReplayChallengeStore', () {
    test('issues a fresh 16-byte base64 token each time', () {
      final store = ReplayChallengeStore();
      final a = store.issue();
      final b = store.issue();
      expect(a, isNot(equals(b)));
      expect(base64.decode(a).length, 16);
      expect(store.outstandingCount, 2);
    });

    test('consume returns the raw bytes for an outstanding token', () {
      final store = ReplayChallengeStore();
      final token = store.issue();
      final bytes = store.consume(token);
      expect(bytes, isNotNull);
      expect(bytes, base64.decode(token));
    });

    test('a token is single-use: the second consume is rejected', () {
      final store = ReplayChallengeStore();
      final token = store.issue();
      expect(store.consume(token), isNotNull);
      // Replay of the same token → rejected (this is the replay defence).
      expect(store.consume(token), isNull);
    });

    test('an unknown token is rejected', () {
      final store = ReplayChallengeStore();
      expect(store.consume(base64.encode(List.filled(16, 9))), isNull);
    });

    test('a malformed token is rejected', () {
      final store = ReplayChallengeStore();
      store.issue();
      // Not base64 at all.
      expect(store.consume('not-base64!!!'), isNull);
      // Valid base64, but not 16 bytes.
      expect(store.consume(base64.encode(List.filled(8, 3))), isNull);
      // The empty string.
      expect(store.consume(''), isNull);
    });

    test('an expired token is rejected', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final store = ReplayChallengeStore(
        ttl: const Duration(minutes: 5),
        clock: () => now,
      );
      final token = store.issue();
      now = now.add(const Duration(minutes: 6));
      expect(store.consume(token), isNull);
    });

    test('an unexpired token survives a clock advance within the TTL', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final store = ReplayChallengeStore(
        ttl: const Duration(minutes: 5),
        clock: () => now,
      );
      final token = store.issue();
      now = now.add(const Duration(minutes: 4));
      expect(store.consume(token), isNotNull);
    });

    test('outstanding challenges are bounded by maxOutstanding', () {
      final store = ReplayChallengeStore(maxOutstanding: 8);
      for (var i = 0; i < 100; i++) {
        store.issue();
      }
      expect(store.outstandingCount, lessThanOrEqualTo(8));
    });

    test('eviction at maxOutstanding drops the oldest challenge', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final store = ReplayChallengeStore(
        maxOutstanding: 2,
        clock: () => now,
      );
      final oldest = store.issue();
      now = now.add(const Duration(seconds: 1));
      final middle = store.issue();
      now = now.add(const Duration(seconds: 1));
      final newest = store.issue(); // evicts [oldest]
      expect(store.consume(oldest), isNull);
      expect(store.consume(middle), isNotNull);
      expect(store.consume(newest), isNotNull);
    });
  });
}
