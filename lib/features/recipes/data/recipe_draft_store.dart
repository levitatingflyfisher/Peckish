import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:peckish/core/providers/core_providers.dart';

/// What the recipe editor holds while it is being typed.
class RecipeDraft {
  const RecipeDraft({
    this.title = '',
    this.servings = '',
    this.ingredients = '',
    this.instructions = '',
  });

  final String title;
  final String servings;
  final String ingredients;
  final String instructions;

  Map<String, String> toJson() => {
        'title': title,
        'servings': servings,
        'ingredients': ingredients,
        'instructions': instructions,
      };

  factory RecipeDraft.fromJson(Map<String, dynamic> j) => RecipeDraft(
        title: j['title'] as String? ?? '',
        servings: j['servings'] as String? ?? '',
        ingredients: j['ingredients'] as String? ?? '',
        instructions: j['instructions'] as String? ?? '',
      );

  @override
  bool operator ==(Object other) =>
      other is RecipeDraft &&
      other.title == title &&
      other.servings == servings &&
      other.ingredients == ingredients &&
      other.instructions == instructions;

  @override
  int get hashCode => Object.hash(title, servings, ingredients, instructions);
}

/// Unsaved recipe work, kept as it is typed (lens audit humane-01: the
/// longest form in the app lost everything to one back gesture). A draft is
/// keyed by what is being edited: `new`, `edit:<recipe id>`, or
/// `import:<source url>`.
abstract interface class RecipeDraftStore {
  RecipeDraft? read(String key);
  Future<void> write(String key, RecipeDraft draft);
  Future<void> clear(String key);

  /// Erase all data takes the drafts with it.
  Future<void> clearAll();
}

/// Drafts in shared preferences, so they survive Android killing the app
/// while you are in the browser copying the rest of the recipe.
class PrefsRecipeDraftStore implements RecipeDraftStore {
  PrefsRecipeDraftStore(this._prefs);
  final SharedPreferences _prefs;

  static const _prefix = 'recipe.draft.';

  @override
  RecipeDraft? read(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return RecipeDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> write(String key, RecipeDraft draft) =>
      _prefs.setString('$_prefix$key', jsonEncode(draft.toJson()));

  @override
  Future<void> clear(String key) => _prefs.remove('$_prefix$key');

  @override
  Future<void> clearAll() async {
    for (final k in _prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await _prefs.remove(k);
    }
  }
}

/// In memory only: for widget tests.
class MemoryRecipeDraftStore implements RecipeDraftStore {
  final _drafts = <String, RecipeDraft>{};

  @override
  RecipeDraft? read(String key) => _drafts[key];

  @override
  Future<void> write(String key, RecipeDraft draft) async =>
      _drafts[key] = draft;

  @override
  Future<void> clear(String key) async => _drafts.remove(key);

  @override
  Future<void> clearAll() async => _drafts.clear();
}

final recipeDraftStoreProvider = Provider<RecipeDraftStore>(
    (ref) => PrefsRecipeDraftStore(ref.watch(sharedPreferencesProvider)));
