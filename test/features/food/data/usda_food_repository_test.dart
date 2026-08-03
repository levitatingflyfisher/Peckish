import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/data/usda_food_repository.dart';

/// A tiny in-memory spine in the exact shape of assets/food/usda_foods.json.
final _fixture = jsonEncode({
  'v': 1,
  'foods': [
    // [fdcId, src, name, kcal, p, c, f, fiber, sugar, sodiumMg]
    [
      171688,
      'sr',
      'Apples, raw, with skin',
      52.0,
      0.26,
      13.81,
      0.17,
      2.4,
      10.39,
      1.0
    ],
    [
      171077,
      'sr',
      'Chicken, broiler or fryers, breast, skinless, boneless, meat only, raw',
      120.0,
      22.5,
      0.0,
      2.62,
      0.0,
      0.0,
      45.0
    ],
    [
      2707343,
      'survey',
      'Egg burrito',
      249.0,
      10.91,
      20.06,
      13.71,
      1.4,
      1.75,
      470.0
    ],
    [
      2727569,
      'foundation',
      'Chicken, breast, meat and skin, raw',
      126.9,
      21.41,
      -0.43,
      4.78,
      null,
      null,
      48.07
    ],
    [
      173410,
      'sr',
      'Cheese, cheddar',
      403.0,
      24.9,
      1.28,
      33.14,
      0.0,
      0.52,
      621.0
    ],
  ],
  'portions': [
    [171688, '1 medium (3" dia)', 182.0],
    [171688, '1 cup slices', 109.0],
    [173410, '1 slice (1 oz)', 28.35],
  ],
});

void main() {
  late AppDatabase db;
  late UsdaFoodRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = UsdaFoodRepository(db);
    await repo.importSpine(_fixture);
  });

  tearDown(() => db.close());

  group('importSpine', () {
    test('loads every food with per-100g macros', () async {
      final apple = await repo.byId(171688);
      expect(apple, isNotNull);
      expect(apple!.name, 'Apples, raw, with skin');
      expect(apple.per100g.kcal, 52.0);
      expect(apple.per100g.proteinG, 0.26);
      expect(apple.source, 'sr');
    });

    test('clamps negative lab artifacts to zero', () async {
      final chicken = await repo.byId(2727569);
      expect(chicken!.per100g.carbG, 0);
    });

    test('is idempotent — importing twice leaves one copy', () async {
      await repo.importSpine(_fixture);
      final results = await repo.search('cheddar');
      expect(results, hasLength(1));
    });

    test('stamps the spine version so boot can skip a re-import', () async {
      expect(await repo.importedSpineVersion(), 1);
    });

    test('spineCurrent is the boot fast-path: false before, true after',
        () async {
      // Boot must be able to answer "is the spine in place?" WITHOUT
      // loading and decoding the 2.5MB asset — that decode cost every
      // launch was the single biggest potato waste in the app.
      final fresh = UsdaFoodRepository(AppDatabase(NativeDatabase.memory()));
      expect(await fresh.spineCurrent(), isFalse);

      expect(await repo.spineCurrent(), isTrue);
    });

    test('the compile-time shipped version matches the real asset', () {
      // The fast-path const and the asset must never drift: the tool that
      // regenerates the asset bumps `v`, and this test forces the const
      // to follow.
      final raw =
          jsonDecode(File('assets/food/usda_foods.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(raw['v'], UsdaFoodRepository.shippedSpineVersion);
    });
  });

  group('search', () {
    test('every word must match, case-insensitive, any order', () async {
      final hits = await repo.search('raw apples');
      expect(hits.map((f) => f.fdcId), contains(171688));
      expect(await repo.search('zzzznothing'), isEmpty);
    });

    test('name-starts-with ranks above mid-name matches', () async {
      final hits = await repo.search('chicken');
      expect(hits.first.name, startsWith('Chicken'));
    });

    test('shorter names rank first among equal matches', () async {
      // "Egg burrito" (survey) should beat the long chicken names for 'egg'.
      final hits = await repo.search('egg');
      expect(hits.first.fdcId, 2707343);
    });
  });

  group('portions', () {
    test('lists household portions for a food, gram-resolved', () async {
      final portions = await repo.portionsOf(171688);
      expect(portions, hasLength(2));
      final medium = portions.firstWhere((p) => p.label.contains('medium'));
      expect(medium.grams, 182.0);
    });

    test('a food without recorded portions returns empty, not an error',
        () async {
      expect(await repo.portionsOf(2707343), isEmpty);
    });
  });
}
