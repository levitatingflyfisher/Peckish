@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/sync/data/lan_sync_client.dart';
import 'package:peckish/features/sync/data/lan_sync_server.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';
import 'package:peckish/features/sync/data/sync_engine.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart'
    show CryptoException;

// The whole stack, over a REAL socket: a server bound to an ephemeral
// loopback port, a client doing the pull-then-push dance, two real
// databases converging through encrypted frames. Plus the two refusals
// that make it safe: a wrong secret opens nothing, and a replayed
// challenge mutates nothing.
void main() {
  // flutter_test swaps in an HttpOverrides that answers every request with
  // an empty 400 — correct for widget tests, fatal for a loopback socket
  // test. Restore real networking for this suite only.
  setUpAll(() => HttpOverrides.global = null);

  late AppDatabase serverDb;
  late AppDatabase clientDb;
  late LanSyncServer server;

  const householdSecret = 'a-household-secret-longer-than-16';

  setUp(() async {
    serverDb = AppDatabase(NativeDatabase.memory());
    clientDb = AppDatabase(NativeDatabase.memory());
    server = LanSyncServer(
      engine: SyncEngine(serverDb),
      clock: SyncClock.of(serverDb),
      secret: () async => householdSecret,
      port: 0, // ephemeral — the test asks the server where it landed
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    await serverDb.close();
    await clientDb.close();
  });

  CustomFood food(String id, String name) => CustomFood(
        id: id,
        name: name,
        servingLabel: '1 serving',
        perServing: const MacroSet(kcal: 100),
        createdAt: DateTime(2026),
      );

  test('two devices converge over the real encrypted wire', () async {
    await CustomFoodRepository(serverDb).create(food('cf-s', 'On the phone'));
    await CustomFoodRepository(clientDb).create(food('cf-c', 'On the tablet'));
    await GroceryRepository(clientDb).addManual('Milk');

    final client = LanSyncClient(
      engine: SyncEngine(clientDb),
      secret: () async => householdSecret,
    );
    final result = await client.syncWith('127.0.0.1', server.port);
    expect(result.pulled, greaterThan(0));
    expect(result.pushed, greaterThan(0));

    final onServer =
        (await CustomFoodRepository(serverDb).getAll()).map((f) => f.name);
    final onClient =
        (await CustomFoodRepository(clientDb).getAll()).map((f) => f.name);
    expect(onServer, containsAll(['On the phone', 'On the tablet']));
    expect(onClient, containsAll(['On the phone', 'On the tablet']));
    expect((await GroceryRepository(serverDb).getAll()).map((g) => g.name),
        contains('Milk'));
  });

  test('the wrong secret opens nothing — unpaired devices cannot sync',
      () async {
    await CustomFoodRepository(serverDb).create(food('cf-s', 'Secret soup'));
    final stranger = LanSyncClient(
      engine: SyncEngine(clientDb),
      secret: () async => 'a-different-secret-entirely!',
    );
    await expectLater(stranger.syncWith('127.0.0.1', server.port),
        throwsA(isA<CryptoException>()));
    expect(await CustomFoodRepository(clientDb).getAll(), isEmpty);
  });

  test('a replayed challenge is refused before it can mutate anything',
      () async {
    final client = LanSyncClient(
      engine: SyncEngine(clientDb),
      secret: () async => householdSecret,
    );
    final status = await client.getStatus('127.0.0.1', server.port);
    final changeset = await SyncEngine(clientDb).buildChangeset();

    final first = await client.pushChangeset(
        '127.0.0.1', server.port, changeset,
        challenge: status.challenge!);
    expect(first.error, isNull);

    // Same challenge again — the replay. 401, no merge.
    final replay = await client.pushChangeset(
        '127.0.0.1', server.port, changeset,
        challenge: status.challenge!);
    expect(replay.error, isNotNull);
  });
}
