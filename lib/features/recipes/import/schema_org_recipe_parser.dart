import 'dart:convert';

import 'package:peckish/features/food/domain/macro_set.dart';

/// What paste-a-URL yields before the user confirms it into the box.
class ImportedRecipe {
  const ImportedRecipe({
    required this.title,
    required this.ingredientLines,
    required this.instructions,
    this.servings,
    this.perServing,
    this.sourceUrl,
  });

  final String title;
  final List<String> ingredientLines;
  final List<String> instructions;
  final double? servings;

  /// Site-declared per-serving nutrition, when the page published it. Null
  /// slots stay null — never fake zeros.
  final MacroSet? perServing;
  final String? sourceUrl;
}

/// Generic schema.org/Recipe extractor over JSON-LD script blocks — the
/// mainstream-site 80% of what recipe-scrapers' per-site subclasses cover.
///
/// Tolerates the shapes real sites actually ship: `@graph` wrappers, @type
/// as a list, recipeYield as string/number/list, recipeInstructions as a
/// plain string / single HowToStep dict / HowToStep list / HowToSection
/// nesting, null-text steps, and malformed sibling JSON-LD blocks. A page
/// with no Recipe entity parses to null — the UI's answer is manual entry,
/// never a crash.
class SchemaOrgRecipeParser {
  const SchemaOrgRecipeParser();

  static final _scriptPattern = RegExp(
    r'<script[^>]*type\s*=\s*["' "'" r']application/ld\+json["' "'" r'][^>]*>(.*?)</script>',
    dotAll: true,
    caseSensitive: false,
  );

  ImportedRecipe? parse(String html, {String? sourceUrl}) {
    for (final match in _scriptPattern.allMatches(html)) {
      final block = match.group(1)!.trim();
      final dynamic decoded;
      try {
        decoded = jsonDecode(block);
      } on FormatException {
        continue; // one broken block must not hide a good sibling block
      }
      final recipe = _findRecipe(decoded);
      if (recipe != null) return _build(recipe, sourceUrl);
    }
    return null;
  }

  Map<String, dynamic>? _findRecipe(dynamic node) {
    if (node is List) {
      for (final item in node) {
        final found = _findRecipe(item);
        if (found != null) return found;
      }
      return null;
    }
    if (node is! Map<String, dynamic>) return null;
    if (_isRecipeType(node['@type'])) return node;
    return _findRecipe(node['@graph']);
  }

  static bool _isRecipeType(dynamic type) =>
      type == 'Recipe' || (type is List && type.contains('Recipe'));

  ImportedRecipe? _build(Map<String, dynamic> node, String? sourceUrl) {
    final title = node['name'];
    if (title is! String || title.trim().isEmpty) return null;
    return ImportedRecipe(
      title: _decodeEntities(title.trim()),
      servings: _servings(node['recipeYield']),
      ingredientLines: [
        for (final line in _stringList(node['recipeIngredient']))
          _decodeEntities(line),
      ],
      instructions: [
        for (final step in _instructions(node['recipeInstructions']))
          _decodeEntities(step),
      ],
      perServing: _nutrition(node['nutrition']),
      sourceUrl: sourceUrl,
    );
  }

  static double? _servings(dynamic yield_) {
    if (yield_ == null) return null;
    if (yield_ is num) return yield_.toDouble();
    if (yield_ is String) {
      final m = RegExp(r'\d+(\.\d+)?').firstMatch(yield_);
      return m == null ? null : double.tryParse(m.group(0)!);
    }
    if (yield_ is List) {
      for (final item in yield_) {
        final parsed = _servings(item);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  static List<String> _stringList(dynamic value) => [
        if (value is List)
          for (final item in value)
            if (item is String && item.trim().isNotEmpty) item.trim(),
      ];

  List<String> _instructions(dynamic value) {
    if (value == null) return const [];
    if (value is String) {
      final t = value.trim();
      return t.isEmpty ? const [] : [t];
    }
    if (value is Map<String, dynamic>) {
      // HowToSection nests steps under itemListElement; HowToStep (or a
      // plain untyped dict) carries text (falling back to name).
      final nested = value['itemListElement'];
      if (nested != null) return _instructions(nested);
      final text = value['text'] ?? value['name'];
      if (text is String && text.trim().isNotEmpty) return [text.trim()];
      return const [];
    }
    if (value is List) {
      return [for (final item in value) ..._instructions(item)];
    }
    return const [];
  }

  static MacroSet? _nutrition(dynamic value) {
    if (value is! Map<String, dynamic>) return null;
    double? leadingNumber(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is! String) return null;
      final m = RegExp(r'\d+(\.\d+)?').firstMatch(v);
      return m == null ? null : double.tryParse(m.group(0)!);
    }

    final set = MacroSet(
      kcal: leadingNumber(value['calories']),
      proteinG: leadingNumber(value['proteinContent']),
      carbG: leadingNumber(value['carbohydrateContent']),
      fatG: leadingNumber(value['fatContent']),
    );
    final empty = set.kcal == null &&
        set.proteinG == null &&
        set.carbG == null &&
        set.fatG == null;
    return empty ? null : set;
  }

  /// The handful of entities that actually appear in embedded JSON-LD titles
  /// and lines. (Full HTML parsing is deliberately out of scope.)
  static String _decodeEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&nbsp;', ' ');
}
