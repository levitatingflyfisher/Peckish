import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/food/domain/usda_food.dart';

/// The bundled USDA spine: import from the shipped JSON asset, then serve
/// offline search / lookup forever after.
///
/// Reference data, not user data: it survives `eraseUserData()` and is
/// wholesale-replaced (delete + re-insert) when the shipped spine version
/// changes, keyed by the [spineVersionKey] stamp in the shell prefs table.
class UsdaFoodRepository {
  UsdaFoodRepository(this._db);

  final AppDatabase _db;

  static const spineVersionKey = 'usda_spine_v';

  /// Parses the spine JSON and loads it, replacing any previous copy if the
  /// shipped version differs. Idempotent: re-importing the same version is a
  /// no-op, so boot can call this unconditionally.
  Future<void> importSpine(String json) async {
    final raw = jsonDecode(json) as Map<String, dynamic>;
    final version = raw['v'] as int;
    if (await importedSpineVersion() == version) return;

    final foods = raw['foods'] as List<dynamic>;
    final portions = raw['portions'] as List<dynamic>;

    await _db.transaction(() async {
      await _db.delete(_db.usdaPortions).go();
      await _db.delete(_db.usdaFoods).go();
      await _db.batch((batch) {
        batch.insertAll(_db.usdaFoods, [
          for (final f in foods.cast<List<dynamic>>())
            UsdaFoodsCompanion.insert(
              fdcId: Value(f[0] as int),
              source: f[1] as String,
              name: f[2] as String,
              nameNorm: (f[2] as String).toLowerCase(),
              kcal: Value(_clampedNum(f[3])),
              proteinG: Value(_clampedNum(f[4])),
              carbG: Value(_clampedNum(f[5])),
              fatG: Value(_clampedNum(f[6])),
              fiberG: Value(_clampedNum(f[7])),
              sugarG: Value(_clampedNum(f[8])),
              sodiumMg: Value(_clampedNum(f[9])),
            ),
        ]);
        batch.insertAll(_db.usdaPortions, [
          for (final p in portions.cast<List<dynamic>>())
            UsdaPortionsCompanion.insert(
              fdcId: p[0] as int,
              label: p[1] as String,
              grams: (p[2] as num).toDouble(),
            ),
        ]);
      });
      await _db.into(_db.userPrefs).insertOnConflictUpdate(
            UserPrefsCompanion.insert(
              key: spineVersionKey,
              value: '$version',
            ),
          );
    });
  }

  /// The spine version currently imported, or null before first import.
  Future<int?> importedSpineVersion() async {
    final row = await (_db.select(_db.userPrefs)
          ..where((p) => p.key.equals(spineVersionKey)))
        .getSingleOrNull();
    return row == null ? null : int.tryParse(row.value);
  }

  Future<UsdaFood?> byId(int fdcId) async {
    final row = await (_db.select(_db.usdaFoods)
          ..where((f) => f.fdcId.equals(fdcId)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// Offline search: every whitespace-separated word must appear in the name
  /// (case-insensitive, any order). Ranked in SQL: name-starts-with-first-word
  /// beats mid-name matches, then shorter names first — so "Egg burrito"
  /// outranks a 90-character laboratory name.
  Future<List<UsdaFood>> search(String query, {int limit = 40}) async {
    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map(_stripLikeMeta)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const [];

    final rows = await (_db.select(_db.usdaFoods)
          ..where((f) => words
              .map<Expression<bool>>((w) => f.nameNorm.contains(w))
              .reduce((a, b) => a & b))
          ..orderBy([
            (f) => OrderingTerm.desc(f.nameNorm.like('${words.first}%')),
            (f) => OrderingTerm.asc(f.nameNorm.length),
            (f) => OrderingTerm.asc(f.nameNorm),
          ])
          ..limit(limit))
        .get();
    return rows.map(_toDomain).toList();
  }

  Future<List<UsdaPortion>> portionsOf(int fdcId) async {
    final rows = await (_db.select(_db.usdaPortions)
          ..where((p) => p.fdcId.equals(fdcId))
          ..orderBy([(p) => OrderingTerm.asc(p.grams)]))
        .get();
    return [
      for (final r in rows) UsdaPortion(label: r.label, grams: r.grams),
    ];
  }

  static double? _clampedNum(dynamic v) {
    if (v == null) return null;
    final d = (v as num).toDouble();
    return d < 0 ? 0 : d;
  }

  static UsdaFood _toDomain(UsdaFoodRow row) => UsdaFood(
        fdcId: row.fdcId,
        source: row.source,
        name: row.name,
        per100g: MacroSet(
          kcal: row.kcal,
          proteinG: row.proteinG,
          carbG: row.carbG,
          fatG: row.fatG,
        ),
        fiberG: row.fiberG,
        sugarG: row.sugarG,
        sodiumMg: row.sodiumMg,
      );

  /// `%`/`_`/`\` are LIKE metacharacters and drift's LIKE has no ESCAPE
  /// clause — strip them from search words instead (no food name needs them
  /// to be found).
  static String _stripLikeMeta(String s) => s.replaceAll(RegExp(r'[%_\\]'), '');
}
