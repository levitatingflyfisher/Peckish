import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/recipes/import/recipe_fetcher.dart';
import 'package:peckish/features/recipes/import/schema_org_recipe_parser.dart';
import 'package:peckish/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:peckish/shared/extensions/qty_format.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// The recipe box: paste a URL and the page becomes a recipe, or write one
/// by hand. Import is preview-then-confirm — nothing enters the box unseen.
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add recipe',
        onPressed: () => _showAddChoices(context, ref),
        child: const Icon(Icons.add),
      ),
      body: (recipes.value ?? const []).isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'An empty box. Paste a recipe link with +, or write one '
                  'down yourself.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: AppColors.stone),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                for (final r in recipes.value!)
                  Card(
                    child: ListTile(
                      minVerticalPadding: AppSpacing.sm,
                      title: Text(r.title),
                      subtitle: Text(_subtitle(r)),
                      trailing: r.perServing?.kcal == null
                          ? null
                          : Chip(
                              label: Text(
                                  '${r.perServing!.kcal!.round()} kcal'),
                              visualDensity: VisualDensity.compact,
                            ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecipeDetailScreen(recipeId: r.id),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 96),
              ],
            ),
    );
  }

  String _subtitle(Recipe r) {
    final bits = <String>[
      if (r.servings != null) '${formatQty(r.servings!)} servings',
      '${r.ingredients.length} ingredients',
    ];
    return bits.join(' · ');
  }

  Future<void> _showAddChoices(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link),
                title: const Text('Paste a recipe link'),
                subtitle:
                    const Text('Fetches that one page, nothing else'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _importFromUrl(context, ref);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Write one down'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const RecipeEditScreen()));
                },
              ),
            ],
          ),
        ),
      );

  Future<void> _importFromUrl(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Paste a recipe link'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(d).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(d).pop(controller.text.trim()),
              child: const Text('Fetch')),
        ],
      ),
    );
    if (url == null || url.isEmpty || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final html = await RecipeFetcher().fetch(Uri.parse(url));
      final imported =
          const SchemaOrgRecipeParser().parse(html, sourceUrl: url);
      if (!context.mounted) return;
      if (imported == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
                "Couldn't find a recipe on that page — try writing it down "
                'instead.')));
        return;
      }
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecipeEditScreen(imported: imported)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }
}

final recipesListProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(recipeRepositoryProvider).watchAll());

/// Manual editor + import-preview confirm surface, one widget.
class RecipeEditScreen extends ConsumerStatefulWidget {
  const RecipeEditScreen({super.key, this.imported, this.existing});

  final ImportedRecipe? imported;
  final Recipe? existing;

  @override
  ConsumerState<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends ConsumerState<RecipeEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _servings;
  late final TextEditingController _ingredients;
  late final TextEditingController _instructions;

  @override
  void initState() {
    super.initState();
    final imp = widget.imported;
    final ex = widget.existing;
    _title = TextEditingController(text: ex?.title ?? imp?.title ?? '');
    _servings = TextEditingController(
        text: (ex?.servings ?? imp?.servings)?.toString() ?? '');
    _ingredients = TextEditingController(
        text: ex != null
            ? ex.ingredients.map((i) => i.text).join('\n')
            : (imp?.ingredientLines.join('\n') ?? ''));
    _instructions = TextEditingController(
        text: ex?.instructions ?? imp?.instructions.join('\n\n') ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final isPreview = widget.imported != null && widget.existing == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing != null
            ? 'Edit recipe'
            : isPreview
                ? 'Check the import'
                : 'New recipe'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (isPreview)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Here is what the page said — fix anything, then save.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.stone),
              ),
            ),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
                labelText: 'Title', border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _servings,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Servings', border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _ingredients,
            maxLines: 10,
            decoration: const InputDecoration(
                labelText: 'Ingredients — one per line',
                alignLabelWithHint: true,
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _instructions,
            maxLines: 12,
            decoration: const InputDecoration(
                labelText: 'Instructions',
                alignLabelWithHint: true,
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            onPressed: _save,
            child: Text(widget.existing != null ? 'Save changes' : 'Save'),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(recipeRepositoryProvider);
    final existing = widget.existing;
    final recipe = Recipe(
      id: existing?.id ?? const Uuid().v4(),
      title: title,
      servings: double.tryParse(_servings.text),
      sourceUrl: existing?.sourceUrl ?? widget.imported?.sourceUrl,
      instructions: _instructions.text.trim(),
      declaredPerServing:
          existing?.declaredPerServing ?? widget.imported?.perServing,
      createdAt: existing?.createdAt ?? DateTime.now(),
      ingredients: [
        for (final line in _ingredients.text.split('\n'))
          if (line.trim().isNotEmpty)
            RecipeIngredient(id: const Uuid().v4(), text: line.trim()),
      ],
    );
    if (existing != null) {
      await repo.update(recipe);
    } else {
      await repo.create(recipe);
    }
    if (mounted) Navigator.of(context).pop();
  }
}
