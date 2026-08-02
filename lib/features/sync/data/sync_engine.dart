import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/sync/data/sync_clock.dart';

/// The payload exchanged between two Peckish households during a sync.
///
/// `data` carries the five household-SHARED sections (custom foods, saved
/// meals + items, recipes + ingredients, plan entries, grocery items) as raw
/// storage-shaped rows with their sync metadata. The diary and targets are
/// NEVER here — the kitchen is shared, the plate is yours.
class SyncChangeset {
  /// Version of the PAYLOAD semantics (row shapes, units, enum indexes).
  /// Distinct from SyncCodec.protocolVersion, which covers only the crypto
  /// wire. Bump when payload meaning changes so an older peer refuses the
  /// merge instead of silently misreading it.
  static const int currentPayloadSchemaVersion = 1;

  final String senderNodeId;
  final String senderHlc;
  final Map<String, dynamic> data;
  final int payloadSchemaVersion;

  const SyncChangeset({
    required this.senderNodeId,
    required this.senderHlc,
    required this.data,
    this.payloadSchemaVersion = currentPayloadSchemaVersion,
  });

  Map<String, dynamic> toJson() => {
        'senderNodeId': senderNodeId,
        'senderHlc': senderHlc,
        'data': data,
        'payloadSchemaVersion': payloadSchemaVersion,
      };

  factory SyncChangeset.fromJson(Map<String, dynamic> json) => SyncChangeset(
        senderNodeId: json['senderNodeId'] as String? ?? '',
        senderHlc: json['senderHlc'] as String? ?? '',
        data: json['data'] as Map<String, dynamic>? ?? {},
        payloadSchemaVersion: json['payloadSchemaVersion'] as int? ?? 1,
      );

  String toJsonString() => jsonEncode(toJson());

  factory SyncChangeset.fromJsonString(String s) =>
      SyncChangeset.fromJson(json.decode(s) as Map<String, dynamic>);
}

/// Result of applying a remote changeset.
class MergeResult {
  final int recordsApplied;
  final String? error;

  const MergeResult({required this.recordsApplied, this.error});

  bool get isSuccess => error == null;
}

/// Builds and applies [SyncChangeset]s with per-row last-write-wins by HLC.
///
/// The LWW rule, in one sentence: a remote row is applied only when there is
/// no local row with that id, or when the remote stamp compares strictly
/// greater than the local one — so a stale peer can neither clobber a newer
/// edit nor resurrect a newer tombstone (the StillLife sev-8 lesson, baked
/// in from day one here).
class SyncEngine {
  SyncEngine(this._db);

  final AppDatabase _db;

  SyncClock get _clock => SyncClock.of(_db);

  // ── Build ────────────────────────────────────────────────────────────────

  Future<SyncChangeset> buildChangeset() async {
    final nodeId = await _clock.nodeId();
    final hlc = await _clock.next();

    final meals = await _db.select(_db.savedMeals).get();
    final mealItems = await _db.select(_db.savedMealItems).get();
    final recipes = await _db.select(_db.recipes).get();
    final ingredients = await _db.select(_db.recipeIngredients).get();

    return SyncChangeset(
      senderNodeId: nodeId,
      senderHlc: hlc,
      data: {
        'customFoods': [
          for (final r in await _db.select(_db.customFoods).get())
            {
              'id': r.id,
              'name': r.name,
              'servingLabel': r.servingLabel,
              'kcal': r.kcal,
              'proteinG': r.proteinG,
              'carbG': r.carbG,
              'fatG': r.fatG,
              'createdAt': r.createdAt.toIso8601String(),
              'archived': r.archived,
              ..._meta(r.hlc, r.nodeId, r.isDeleted),
            },
        ],
        'savedMeals': [
          for (final m in meals)
            {
              'id': m.id,
              'name': m.name,
              'position': m.position,
              'createdAt': m.createdAt.toIso8601String(),
              'lastUsedAt': m.lastUsedAt?.toIso8601String(),
              'archived': m.archived,
              ..._meta(m.hlc, m.nodeId, m.isDeleted),
              'items': [
                for (final i in mealItems.where((i) => i.mealId == m.id))
                  {
                    'id': i.id,
                    'position': i.position,
                    'foodKind': i.foodKind.index,
                    'usdaFdcId': i.usdaFdcId,
                    'customFoodId': i.customFoodId,
                    'label': i.label,
                    'qty': i.qty,
                    'unitLabel': i.unitLabel,
                    'grams': i.grams,
                    'kcal': i.kcal,
                    'proteinG': i.proteinG,
                    'carbG': i.carbG,
                    'fatG': i.fatG,
                  },
              ],
            },
        ],
        'recipes': [
          for (final r in recipes)
            {
              'id': r.id,
              'title': r.title,
              'servings': r.servings,
              'sourceUrl': r.sourceUrl,
              'instructions': r.instructions,
              'declaredKcal': r.declaredKcal,
              'declaredProteinG': r.declaredProteinG,
              'declaredCarbG': r.declaredCarbG,
              'declaredFatG': r.declaredFatG,
              'createdAt': r.createdAt.toIso8601String(),
              'archived': r.archived,
              ..._meta(r.hlc, r.nodeId, r.isDeleted),
              'ingredients': [
                for (final i
                    in ingredients.where((i) => i.recipeId == r.id))
                  {
                    'id': i.id,
                    'position': i.position,
                    'line': i.line,
                    'foodKind': i.foodKind?.index,
                    'usdaFdcId': i.usdaFdcId,
                    'customFoodId': i.customFoodId,
                    'grams': i.grams,
                    'kcal': i.kcal,
                    'proteinG': i.proteinG,
                    'carbG': i.carbG,
                    'fatG': i.fatG,
                  },
              ],
            },
        ],
        'planEntries': [
          for (final r in await _db.select(_db.planEntries).get())
            {
              'id': r.id,
              'day': r.day,
              'slot': r.slot.index,
              'kind': r.kind.index,
              'refId': r.refId,
              'note': r.note,
              ..._meta(r.hlc, r.nodeId, r.isDeleted),
            },
        ],
        'groceryItems': [
          for (final r in await _db.select(_db.groceryItems).get())
            {
              'id': r.id,
              'name': r.name,
              'aisle': r.aisle.index,
              'checked': r.checked,
              'manual': r.manual,
              'sourceRecipeId': r.sourceRecipeId,
              'createdAt': r.createdAt.toIso8601String(),
              ..._meta(r.hlc, r.nodeId, r.isDeleted),
            },
        ],
      },
    );
  }

  static Map<String, dynamic> _meta(
          String? hlc, String? nodeId, bool isDeleted) =>
      {'hlc': hlc, 'nodeId': nodeId, 'isDeleted': isDeleted};

  /// One-time backfill when sync is first enabled: rows written before sync
  /// existed carry no stamp and would only ever insert-if-absent on peers.
  /// Returns how many rows were stamped.
  Future<int> stampUnstamped() async {
    var stamped = 0;
    Future<void> run(TableInfo table) async {
      final rows = await _db
          .customSelect('SELECT id FROM ${table.actualTableName} '
              'WHERE hlc IS NULL')
          .get();
      for (final row in rows) {
        final s = await _clock.stamp();
        await _db.customUpdate(
          'UPDATE ${table.actualTableName} SET hlc = ?, node_id = ? '
          'WHERE id = ?',
          variables: [
            Variable(s.hlc),
            Variable(s.nodeId),
            Variable(row.read<String>('id')),
          ],
          updates: {table},
        );
        stamped++;
      }
    }

    await run(_db.customFoods);
    await run(_db.savedMeals);
    await run(_db.recipes);
    await run(_db.planEntries);
    await run(_db.groceryItems);
    return stamped;
  }

  // ── Apply ────────────────────────────────────────────────────────────────

  Future<MergeResult> apply(SyncChangeset remote) async {
    // Fail closed on a payload from a newer app version: its semantics may
    // have changed, and misreading them would corrupt data silently.
    // Nothing is written before this check.
    if (remote.payloadSchemaVersion >
        SyncChangeset.currentPayloadSchemaVersion) {
      return MergeResult(
        recordsApplied: 0,
        error: 'The other device runs a newer version of Peckish (sync '
            'payload v${remote.payloadSchemaVersion}, this app understands '
            'v${SyncChangeset.currentPayloadSchemaVersion}). Update this '
            'app, then sync again.',
      );
    }

    var applied = 0;
    try {
      await _db.transaction(() async {
        applied += await _applyCustomFoods(remote.data['customFoods']);
        applied += await _applySavedMeals(remote.data['savedMeals']);
        applied += await _applyRecipes(remote.data['recipes']);
        applied += await _applyPlanEntries(remote.data['planEntries']);
        applied += await _applyGroceryItems(remote.data['groceryItems']);
      });
      await _clock.merge(remote.senderHlc);
      return MergeResult(recordsApplied: applied);
    } catch (e) {
      return MergeResult(recordsApplied: 0, error: e.toString());
    }
  }

  /// The one LWW decision: apply iff no local row, or remote strictly newer.
  /// A remote row with no stamp can only ever fill a hole.
  static bool _wins(String? remoteHlc, String? localHlc, bool localExists) {
    if (!localExists) return true;
    if (remoteHlc == null || remoteHlc.isEmpty) return false;
    if (localHlc == null || localHlc.isEmpty) return true;
    return remoteHlc.compareTo(localHlc) > 0;
  }

  /// The one skeleton behind all five section appliers: iterate the remote
  /// rows, look up the local row by id, let [_wins] decide, upsert the
  /// winner. Parents whose children travel with them pass [replaceChildren],
  /// invoked after the parent upsert with the running applied count (it
  /// feeds the fallback child id in [_replaceChildrenOf]).
  Future<int> _applySection<T extends Table, R>(
    Object? section,
    TableInfo<T, R> table,
    String? Function(R local) localHlc,
    Insertable<R> Function(String id, Map<String, dynamic> row) toCompanion, {
    Future<void> Function(String id, Map<String, dynamic> row, int applied)?
        replaceChildren,
  }) async {
    final idColumn = table.columnsByName['id']! as GeneratedColumn<String>;
    var applied = 0;
    for (final row in _rows(section)) {
      final id = row['id'] as String?;
      if (id == null) continue;
      final local = await (_db.select(table)
            ..where((_) => idColumn.equals(id)))
          .getSingleOrNull();
      if (!_wins(row['hlc'] as String?,
          local == null ? null : localHlc(local), local != null)) {
        continue;
      }
      await _db.into(table).insertOnConflictUpdate(toCompanion(id, row));
      if (replaceChildren != null) await replaceChildren(id, row, applied);
      applied++;
    }
    return applied;
  }

  /// Children travel with their parent as one unit: replace wholesale. A
  /// child arriving without its own id gets a positional fallback derived
  /// from the parent and the running applied count.
  Future<void> _replaceChildrenOf<T extends Table, R>(
    String parentId,
    int applied,
    Object? items,
    TableInfo<T, R> table,
    GeneratedColumn<String> parentColumn,
    Insertable<R> Function(String childId, Map<String, dynamic> item)
        toCompanion,
  ) async {
    await (_db.delete(table)..where((_) => parentColumn.equals(parentId)))
        .go();
    for (final item in _rows(items)) {
      await _db.into(table).insert(toCompanion(
          item['id'] as String? ?? '${parentId}_${applied}_i', item));
    }
  }

  Future<int> _applyCustomFoods(Object? section) => _applySection(
        section,
        _db.customFoods,
        (local) => local.hlc,
        (id, row) => CustomFoodsCompanion(
          id: Value(id),
          name: Value(row['name'] as String? ?? ''),
          servingLabel: Value(row['servingLabel'] as String? ?? ''),
          kcal: Value(_d(row['kcal'])),
          proteinG: Value(_d(row['proteinG'])),
          carbG: Value(_d(row['carbG'])),
          fatG: Value(_d(row['fatG'])),
          createdAt: Value(_date(row['createdAt'])),
          archived: Value(row['archived'] as bool? ?? false),
          hlc: Value(row['hlc'] as String?),
          nodeId: Value(row['nodeId'] as String?),
          isDeleted: Value(row['isDeleted'] as bool? ?? false),
        ),
      );

  Future<int> _applySavedMeals(Object? section) => _applySection(
        section,
        _db.savedMeals,
        (local) => local.hlc,
        (id, row) => SavedMealsCompanion(
          id: Value(id),
          name: Value(row['name'] as String? ?? ''),
          position: Value(row['position'] as int? ?? 0),
          createdAt: Value(_date(row['createdAt'])),
          lastUsedAt: Value(row['lastUsedAt'] == null
              ? null
              : _date(row['lastUsedAt'])),
          archived: Value(row['archived'] as bool? ?? false),
          hlc: Value(row['hlc'] as String?),
          nodeId: Value(row['nodeId'] as String?),
          isDeleted: Value(row['isDeleted'] as bool? ?? false),
        ),
        // Items travel with their meal: replace wholesale.
        replaceChildren: (id, row, applied) => _replaceChildrenOf(
          id,
          applied,
          row['items'],
          _db.savedMealItems,
          _db.savedMealItems.mealId,
          (childId, item) => SavedMealItemsCompanion(
            id: Value(childId),
            mealId: Value(id),
            position: Value(item['position'] as int? ?? 0),
            foodKind: Value(_enumIndex(
                FoodKindDb.values, item['foodKind'], FoodKindDb.quick)),
            usdaFdcId: Value(item['usdaFdcId'] as int?),
            customFoodId: Value(item['customFoodId'] as String?),
            label: Value(item['label'] as String? ?? ''),
            qty: Value(_d(item['qty']) ?? 1),
            unitLabel: Value(item['unitLabel'] as String? ?? 'serving'),
            grams: Value(_d(item['grams'])),
            kcal: Value(_d(item['kcal'])),
            proteinG: Value(_d(item['proteinG'])),
            carbG: Value(_d(item['carbG'])),
            fatG: Value(_d(item['fatG'])),
          ),
        ),
      );

  Future<int> _applyRecipes(Object? section) => _applySection(
        section,
        _db.recipes,
        (local) => local.hlc,
        (id, row) => RecipesCompanion(
          id: Value(id),
          title: Value(row['title'] as String? ?? ''),
          servings: Value(_d(row['servings'])),
          sourceUrl: Value(row['sourceUrl'] as String?),
          instructions: Value(row['instructions'] as String? ?? ''),
          declaredKcal: Value(_d(row['declaredKcal'])),
          declaredProteinG: Value(_d(row['declaredProteinG'])),
          declaredCarbG: Value(_d(row['declaredCarbG'])),
          declaredFatG: Value(_d(row['declaredFatG'])),
          createdAt: Value(_date(row['createdAt'])),
          archived: Value(row['archived'] as bool? ?? false),
          hlc: Value(row['hlc'] as String?),
          nodeId: Value(row['nodeId'] as String?),
          isDeleted: Value(row['isDeleted'] as bool? ?? false),
        ),
        // Ingredients travel with their recipe: replace wholesale.
        replaceChildren: (id, row, applied) => _replaceChildrenOf(
          id,
          applied,
          row['ingredients'],
          _db.recipeIngredients,
          _db.recipeIngredients.recipeId,
          (childId, item) => RecipeIngredientsCompanion(
            id: Value(childId),
            recipeId: Value(id),
            position: Value(item['position'] as int? ?? 0),
            line: Value(item['line'] as String? ?? ''),
            foodKind: Value(item['foodKind'] == null
                ? null
                : _enumIndex(
                    FoodKindDb.values, item['foodKind'], FoodKindDb.quick)),
            usdaFdcId: Value(item['usdaFdcId'] as int?),
            customFoodId: Value(item['customFoodId'] as String?),
            grams: Value(_d(item['grams'])),
            kcal: Value(_d(item['kcal'])),
            proteinG: Value(_d(item['proteinG'])),
            carbG: Value(_d(item['carbG'])),
            fatG: Value(_d(item['fatG'])),
          ),
        ),
      );

  Future<int> _applyPlanEntries(Object? section) => _applySection(
        section,
        _db.planEntries,
        (local) => local.hlc,
        (id, row) => PlanEntriesCompanion(
          id: Value(id),
          day: Value(row['day'] as String? ?? ''),
          slot: Value(_enumIndex(
              PlanSlotDb.values, row['slot'], PlanSlotDb.other)),
          kind: Value(_enumIndex(
              PlanKindDb.values, row['kind'], PlanKindDb.note)),
          refId: Value(row['refId'] as String?),
          note: Value(row['note'] as String?),
          hlc: Value(row['hlc'] as String?),
          nodeId: Value(row['nodeId'] as String?),
          isDeleted: Value(row['isDeleted'] as bool? ?? false),
        ),
      );

  Future<int> _applyGroceryItems(Object? section) => _applySection(
        section,
        _db.groceryItems,
        (local) => local.hlc,
        (id, row) => GroceryItemsCompanion(
          id: Value(id),
          name: Value(row['name'] as String? ?? ''),
          aisle: Value(_enumIndex(
              GroceryAisleDb.values, row['aisle'], GroceryAisleDb.other)),
          checked: Value(row['checked'] as bool? ?? false),
          manual: Value(row['manual'] as bool? ?? false),
          sourceRecipeId: Value(row['sourceRecipeId'] as String?),
          createdAt: Value(_date(row['createdAt'])),
          hlc: Value(row['hlc'] as String?),
          nodeId: Value(row['nodeId'] as String?),
          isDeleted: Value(row['isDeleted'] as bool? ?? false),
        ),
      );

  // ── Tolerant decoding ────────────────────────────────────────────────────

  static Iterable<Map<String, dynamic>> _rows(Object? section) sync* {
    if (section is! List) return;
    for (final row in section) {
      if (row is Map) yield Map<String, dynamic>.from(row);
    }
  }

  static double? _d(Object? v) => switch (v) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      };

  static DateTime _date(Object? v) =>
      v is String ? (DateTime.tryParse(v) ?? DateTime(2000)) : DateTime(2000);

  /// A foreign enum index (from a hypothetical newer peer that appended a
  /// value) degrades to [fallback] instead of crashing — the version gate
  /// should catch this first, but defence in depth is cheap.
  static T _enumIndex<T extends Enum>(List<T> values, Object? raw, T fallback) {
    final i = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    return i != null && i >= 0 && i < values.length ? values[i] : fallback;
  }
}
