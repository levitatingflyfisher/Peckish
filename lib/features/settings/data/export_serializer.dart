import 'dart:convert';

import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/shared/extensions/datetime_ext.dart';

/// The date-stamped filename for a data export, e.g.
/// `peckish-export-2026-07-25.json`. Takes the date explicitly (not
/// `DateTime.now`) so tests are deterministic; the UI passes `DateTime.now()`.
String exportFileName(DateTime date) => 'peckish-export-${date.toDateDay()}.json';

/// The whole on-device USER dataset, ready to serialize to a portable JSON
/// document the user can keep or move. The bundled USDA spine is reference
/// data and deliberately NOT exported — it ships with every install.
///
/// Absent sections decode to empties so older/hand-trimmed files always
/// restore; unknown keys are ignored (additive keys never require a version
/// bump — SANCTUARY-BRIEF §2.8).
class PeckishExport {
  /// Peckish's WIRE schema counter — deliberately a hardcoded 1, NOT
  /// `AppDatabase.schemaVersion`. The drift version counts on-device
  /// migrations that don't change this JSON shape. Bump only when the
  /// exported JSON itself changes incompatibly.
  static const schemaVersion = 1;

  final DateTime? createdAt;
  final List<CustomFood> customFoods;
  final List<DiaryEntry> diaryEntries;
  final List<SavedMeal> savedMeals;
  final List<Recipe> recipes;
  final List<PlanEntry> planEntries;
  final List<GroceryItem> groceryItems;
  final List<FoodUsage> foodUsages;
  final MacroSet targets;

  const PeckishExport({
    this.createdAt,
    this.customFoods = const [],
    this.diaryEntries = const [],
    this.savedMeals = const [],
    this.recipes = const [],
    this.planEntries = const [],
    this.groceryItems = const [],
    this.foodUsages = const [],
    this.targets = const MacroSet(),
  });

  String toPrettyJson() => const JsonEncoder.withIndent('  ').convert(toMap());

  Map<String, Object?> toMap() => {
        'app': 'peckish',
        'schemaVersion': schemaVersion,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        'customFoods': [for (final f in customFoods) _foodMap(f)],
        'diaryEntries': [for (final e in diaryEntries) _entryMap(e)],
        'savedMeals': [for (final m in savedMeals) _mealMap(m)],
        'recipes': [for (final r in recipes) _recipeMap(r)],
        'planEntries': [for (final p in planEntries) _planMap(p)],
        'groceryItems': [for (final g in groceryItems) _groceryMap(g)],
        // Added post-v0.2; an additive section, so schemaVersion stays put.
        'foodUsages': [for (final u in foodUsages) _usageMap(u)],
        'targets': _macros(targets),
      };

  factory PeckishExport.fromJson(String json) {
    final raw = jsonDecode(json);
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('export root must be a JSON object');
    }
    return PeckishExport.fromMap(raw);
  }

  factory PeckishExport.fromMap(Map<String, dynamic> raw) {
    if (raw['app'] != 'peckish') {
      throw const FormatException('not a Peckish export');
    }
    final version = raw['schemaVersion'];
    if (version is! int || version > schemaVersion) {
      throw FormatException(
        'export schema $version is newer than this app understands '
        '($schemaVersion) — update Peckish, then restore',
      );
    }
    final stamp = raw['createdAt'];
    return PeckishExport(
      createdAt: stamp is String ? DateTime.tryParse(stamp) : null,
      customFoods: [
        for (final f in _section(raw, 'customFoods')) _foodFrom(f),
      ],
      diaryEntries: [
        for (final e in _section(raw, 'diaryEntries')) _entryFrom(e),
      ],
      savedMeals: [
        for (final m in _section(raw, 'savedMeals')) _mealFrom(m),
      ],
      recipes: [
        for (final r in _section(raw, 'recipes')) _recipeFrom(r),
      ],
      planEntries: [
        for (final p in _section(raw, 'planEntries')) _planFrom(p),
      ],
      groceryItems: [
        for (final g in _section(raw, 'groceryItems')) _groceryFrom(g),
      ],
      foodUsages: [
        for (final u in _section(raw, 'foodUsages')) _usageFrom(u),
      ],
      targets: _macrosFrom(raw['targets']),
    );
  }

  static List<Map<String, dynamic>> _section(
      Map<String, dynamic> raw, String key) {
    final v = raw[key];
    if (v == null) return const [];
    if (v is! List) throw FormatException("export section '$key' is not a list");
    return v.cast<Map<String, dynamic>>();
  }

  // ── section shapes ────────────────────────────────────────────────────────

  static Map<String, Object?> _macros(MacroSet m) => {
        if (m.kcal != null) 'kcal': m.kcal,
        if (m.proteinG != null) 'proteinG': m.proteinG,
        if (m.carbG != null) 'carbG': m.carbG,
        if (m.fatG != null) 'fatG': m.fatG,
      };

  static MacroSet _macrosFrom(dynamic raw) {
    if (raw is! Map<String, dynamic>) return const MacroSet();
    double? num_(String k) => (raw[k] as num?)?.toDouble();
    return MacroSet(
      kcal: num_('kcal'),
      proteinG: num_('proteinG'),
      carbG: num_('carbG'),
      fatG: num_('fatG'),
    );
  }

  static Map<String, Object?> _foodMap(CustomFood f) => {
        'id': f.id,
        'name': f.name,
        'servingLabel': f.servingLabel,
        'perServing': _macros(f.perServing),
        'createdAt': f.createdAt.toIso8601String(),
        'archived': f.archived,
      };

  static CustomFood _foodFrom(Map<String, dynamic> raw) => CustomFood(
        id: raw['id'] as String,
        name: raw['name'] as String,
        servingLabel: raw['servingLabel'] as String,
        perServing: _macrosFrom(raw['perServing']),
        createdAt: DateTime.parse(raw['createdAt'] as String),
        archived: raw['archived'] as bool? ?? false,
      );

  static Map<String, Object?> _refMap(FoodRef ref) => {
        'kind': ref.kind.name,
        if (ref.usdaFdcId != null) 'usdaFdcId': ref.usdaFdcId,
        if (ref.customFoodId != null) 'customFoodId': ref.customFoodId,
      };

  static FoodRef _refFrom(Map<String, dynamic> raw) =>
      switch (raw['kind'] as String) {
        'usda' => FoodRef.usda(raw['usdaFdcId'] as int),
        'custom' => FoodRef.custom(raw['customFoodId'] as String),
        _ => const FoodRef.quick(),
      };

  static Map<String, Object?> _entryMap(DiaryEntry e) => {
        'id': e.id,
        'day': e.day,
        'at': e.at.toIso8601String(),
        'food': _refMap(e.food),
        'label': e.label,
        'qty': e.qty,
        'unitLabel': e.unitLabel,
        if (e.grams != null) 'grams': e.grams,
        'macros': _macros(e.macros),
        'source': e.source.name,
        'createdAt': e.createdAt.toIso8601String(),
      };

  static DiaryEntry _entryFrom(Map<String, dynamic> raw) => DiaryEntry(
        id: raw['id'] as String,
        day: raw['day'] as String,
        at: DateTime.parse(raw['at'] as String),
        food: _refFrom(raw['food'] as Map<String, dynamic>),
        label: raw['label'] as String,
        qty: (raw['qty'] as num).toDouble(),
        unitLabel: raw['unitLabel'] as String,
        grams: (raw['grams'] as num?)?.toDouble(),
        macros: _macrosFrom(raw['macros']),
        source: EntrySource.values
            .firstWhere((s) => s.name == raw['source'],
                orElse: () => EntrySource.manual),
        createdAt: DateTime.parse(raw['createdAt'] as String),
      );

  static Map<String, Object?> _mealMap(SavedMeal m) => {
        'id': m.id,
        'name': m.name,
        'position': m.position,
        'createdAt': m.createdAt.toIso8601String(),
        if (m.lastUsedAt != null) 'lastUsedAt': m.lastUsedAt!.toIso8601String(),
        'archived': m.archived,
        'items': [
          for (final i in m.items)
            {
              'id': i.id,
              'food': _refMap(i.food),
              'label': i.label,
              'qty': i.qty,
              'unitLabel': i.unitLabel,
              if (i.grams != null) 'grams': i.grams,
              'macros': _macros(i.macros),
            },
        ],
      };

  static Map<String, Object?> _planMap(PlanEntry p) => {
        'id': p.id,
        'day': p.day,
        'slot': p.slot.name,
        'kind': p.kind.name,
        if (p.refId != null) 'refId': p.refId,
        if (p.note != null) 'note': p.note,
      };

  static PlanEntry _planFrom(Map<String, dynamic> raw) => PlanEntry(
        id: raw['id'] as String,
        day: raw['day'] as String,
        slot: PlanSlot.values.firstWhere((s) => s.name == raw['slot'],
            orElse: () => PlanSlot.other),
        kind: PlanKind.values.firstWhere((k) => k.name == raw['kind'],
            orElse: () => PlanKind.note),
        refId: raw['refId'] as String?,
        note: raw['note'] as String?,
      );

  static Map<String, Object?> _groceryMap(GroceryItem g) => {
        'id': g.id,
        'name': g.name,
        'aisle': g.aisle.name,
        'checked': g.checked,
        'manual': g.manual,
        if (g.sourceRecipeId != null) 'sourceRecipeId': g.sourceRecipeId,
        'createdAt': g.createdAt.toIso8601String(),
      };

  static GroceryItem _groceryFrom(Map<String, dynamic> raw) => GroceryItem(
        id: raw['id'] as String,
        name: raw['name'] as String,
        aisle: GroceryAisle.values.firstWhere((a) => a.name == raw['aisle'],
            orElse: () => GroceryAisle.other),
        checked: raw['checked'] as bool? ?? false,
        manual: raw['manual'] as bool? ?? false,
        sourceRecipeId: raw['sourceRecipeId'] as String?,
        createdAt: DateTime.parse(raw['createdAt'] as String),
      );

  // The identityKey is derived (FoodRef.identityKey), never stored twice.
  static Map<String, Object?> _usageMap(FoodUsage u) => {
        'food': _refMap(u.food),
        'label': u.label,
        'qty': u.qty,
        'unitLabel': u.unitLabel,
        if (u.grams != null) 'grams': u.grams,
        'macros': _macros(u.macros),
        'useCount': u.useCount,
        'lastUsedAt': u.lastUsedAt.toIso8601String(),
        'hidden': u.hidden,
      };

  static FoodUsage _usageFrom(Map<String, dynamic> raw) {
    final food = _refFrom(raw['food'] as Map<String, dynamic>);
    final label = raw['label'] as String;
    return FoodUsage(
      identityKey: food.identityKey(label),
      food: food,
      label: label,
      qty: (raw['qty'] as num).toDouble(),
      unitLabel: raw['unitLabel'] as String,
      grams: (raw['grams'] as num?)?.toDouble(),
      macros: _macrosFrom(raw['macros']),
      useCount: raw['useCount'] as int? ?? 1,
      lastUsedAt: DateTime.parse(raw['lastUsedAt'] as String),
      hidden: raw['hidden'] as bool? ?? false,
    );
  }

  static Map<String, Object?> _recipeMap(Recipe r) => {
        'id': r.id,
        'title': r.title,
        if (r.servings != null) 'servings': r.servings,
        if (r.sourceUrl != null) 'sourceUrl': r.sourceUrl,
        'instructions': r.instructions,
        if (r.declaredPerServing != null)
          'declaredPerServing': _macros(r.declaredPerServing!),
        'createdAt': r.createdAt.toIso8601String(),
        'archived': r.archived,
        'ingredients': [
          for (final i in r.ingredients)
            {
              'id': i.id,
              'text': i.text,
              if (i.food != null) 'food': _refMap(i.food!),
              if (i.grams != null) 'grams': i.grams,
              if (i.macros != null) 'macros': _macros(i.macros!),
            },
        ],
      };

  static Recipe _recipeFrom(Map<String, dynamic> raw) => Recipe(
        id: raw['id'] as String,
        title: raw['title'] as String,
        servings: (raw['servings'] as num?)?.toDouble(),
        sourceUrl: raw['sourceUrl'] as String?,
        instructions: raw['instructions'] as String? ?? '',
        declaredPerServing: raw['declaredPerServing'] == null
            ? null
            : _macrosFrom(raw['declaredPerServing']),
        createdAt: DateTime.parse(raw['createdAt'] as String),
        archived: raw['archived'] as bool? ?? false,
        ingredients: [
          for (final i in (raw['ingredients'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
            RecipeIngredient(
              id: i['id'] as String,
              text: i['text'] as String,
              food: i['food'] == null
                  ? null
                  : _refFrom(i['food'] as Map<String, dynamic>),
              grams: (i['grams'] as num?)?.toDouble(),
              macros: i['macros'] == null ? null : _macrosFrom(i['macros']),
            ),
        ],
      );

  static SavedMeal _mealFrom(Map<String, dynamic> raw) => SavedMeal(
        id: raw['id'] as String,
        name: raw['name'] as String,
        position: raw['position'] as int? ?? 0,
        createdAt: DateTime.parse(raw['createdAt'] as String),
        lastUsedAt: raw['lastUsedAt'] is String
            ? DateTime.tryParse(raw['lastUsedAt'] as String)
            : null,
        archived: raw['archived'] as bool? ?? false,
        items: [
          for (final i in (raw['items'] as List? ?? const [])
              .cast<Map<String, dynamic>>())
            SavedMealItem(
              id: i['id'] as String,
              food: _refFrom(i['food'] as Map<String, dynamic>),
              label: i['label'] as String,
              qty: (i['qty'] as num).toDouble(),
              unitLabel: i['unitLabel'] as String,
              grams: (i['grams'] as num?)?.toDouble(),
              macros: _macrosFrom(i['macros']),
            ),
        ],
      );
}
