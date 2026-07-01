import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';

// The clock is the whole total-order story: node identity is stable for the
// life of the install, stamps only ever move forward (even across a
// restart), and merging a peer's clock pulls ours up so our next write
// beats everything we've seen.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('node id is minted once and stable across instances', () async {
    final a = SyncClock(db);
    final id1 = await a.nodeId();
    final id2 = await SyncClock(db).nodeId();
    expect(id1, isNotEmpty);
    expect(id2, id1, reason: 'same db, same identity');
  });

  test('stamps are strictly increasing, across instances too', () async {
    final clock = SyncClock(db);
    final s1 = await clock.next();
    final s2 = await clock.next();
    expect(s2.compareTo(s1), greaterThan(0));

    // A "restarted app" (fresh instance over the same db) keeps going up.
    final s3 = await SyncClock(db).next();
    expect(s3.compareTo(s2), greaterThan(0));
  });

  test('merging a peer clock pulls ours forward past it', () async {
    final clock = SyncClock(db);
    await clock.next();
    // A peer slightly ahead (within crdt's 1-minute drift bound) — after
    // merging, our next stamp must sort after theirs, so our subsequent
    // writes win as they should.
    final ahead = DateTime.now().toUtc().add(const Duration(seconds: 30));
    final remote = '${ahead.toIso8601String()}-0000-peer';
    await clock.merge(remote);
    final next = await clock.next();
    expect(next.compareTo(remote), greaterThan(0));
  });

  test('a peer clock beyond the drift bound is refused, not followed',
      () async {
    // crdt's deliberate protection: a peer whose wall clock is insanely
    // wrong (>1 min ahead) cannot drag ours into the future. Their rows
    // still win LWW string-compares; only the clock itself refuses to jump.
    final clock = SyncClock(db);
    final before = await clock.next();
    await clock.merge('2099-01-01T00:00:00.000Z-0000-peer');
    final after = await clock.next();
    expect(after.compareTo(before), greaterThan(0),
        reason: 'the clock keeps working after refusing the drift');
    expect(after.startsWith('2099'), isFalse);
  });

  test('a garbage remote clock is ignored, not fatal', () async {
    final clock = SyncClock(db);
    final before = await clock.next();
    await clock.merge('not-a-clock');
    final after = await clock.next();
    expect(after.compareTo(before), greaterThan(0));
  });
}
