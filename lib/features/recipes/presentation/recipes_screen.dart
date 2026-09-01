import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:openhearth_design/openhearth_design.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/recipes/data/recipe_draft_store.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';
import 'package:peckish/features/recipes/import/recipe_fetcher.dart';
import 'package:peckish/features/recipes/import/schema_org_recipe_parser.dart';
import 'package:peckish/features/recipes/presentation/recipe_detail_screen.dart';
import 'package:peckish/shared/extensions/qty_format.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/theme_toggle_action.dart';
import 'package:peckish/shared/widgets/input_modal.dart';

/// The recipe box: paste a URL and the page becomes a recipe, or write one
/// by hand. Import is preview-then-confirm — nothing enters the box unseen.
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recipesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recipes'),
        actions: const [ThemeToggleAction()],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add recipe',
        onPressed: () => _showAddChoices(context, ref),
        child: const Icon(Icons.add),
      ),
      body: OhPage(
          padding: EdgeInsets.zero,
          child: (recipes.value ?? const []).isEmpty
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
                          ?.copyWith(color: AppColors.secondaryText(context)),
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
                          // kcal per serving, the same words the recipe's
                          // own page uses (lens audit visual-display-04). A
                          // line of text that wraps, not a Chip: a Chip
                          // forces one line and would shear the longer
                          // label at large text.
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_subtitle(r)),
                              if (r.perServing?.kcal case final kcal?)
                                Text('${kcal.round()} kcal per serving',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: AppColors.paprika)),
                            ],
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  RecipeDetailScreen(recipeId: r.id),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 96),
                  ],
                )),
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
                subtitle: const Text('Fetches that one page, nothing else'),
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
    final result = await showInputDialog<_ImportResult>(
      context,
      builder: (_) => const _PasteLinkDialog(),
    );
    if (result == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RecipeEditScreen(imported: result.recipe)));
  }
}

/// What the paste dialog hands back: a parsed recipe to check, or (with
/// [recipe] null) the person's choice to write it down by hand.
class _ImportResult {
  const _ImportResult(this.recipe);
  final ImportedRecipe? recipe;
}

/// Paste a link, fetch it, and stay put until there is a recipe to check.
///
/// The dialog stays open through the fetch: the button shows it is busy,
/// Cancel works at any point, and a failure is one plain sentence under the
/// link, which is still there to correct. The raw exception goes to the
/// log, never to the screen (lens audit writing-01, and ten lenses with it).
class _PasteLinkDialog extends ConsumerStatefulWidget {
  const _PasteLinkDialog();

  @override
  ConsumerState<_PasteLinkDialog> createState() => _PasteLinkDialogState();
}

class _PasteLinkDialogState extends ConsumerState<_PasteLinkDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _problem;

  /// Bumped by every fetch and by Cancel, so an answer that arrives after
  /// the person moved on is dropped.
  int _attempt = 0;

  @override
  void dispose() {
    _attempt++;
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    final attempt = ++_attempt;
    setState(() {
      _busy = true;
      _problem = null;
    });
    String? problem;
    ImportedRecipe? imported;
    try {
      final html = await ref.read(recipeFetcherProvider).fetch(Uri.parse(url));
      imported = const SchemaOrgRecipeParser().parse(html, sourceUrl: url);
      if (imported == null) {
        problem = 'Couldn’t find a recipe on that page. Try another link, '
            'or write it down yourself.';
      }
    } catch (e, st) {
      developer.log('recipe import failed',
          name: 'peckish.recipes', error: e, stackTrace: st);
      problem = importProblem(e);
    }
    if (!mounted || attempt != _attempt) return;
    if (imported != null) {
      Navigator.of(context).pop(_ImportResult(imported));
      return;
    }
    setState(() {
      _busy = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste a recipe link'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_busy,
        keyboardType: TextInputType.url,
        onSubmitted: (_) => _fetch(),
        decoration: InputDecoration(
          hintText: 'https://…',
          errorText: _problem,
          errorMaxLines: 4,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              _attempt++;
              Navigator.of(context).pop();
            },
            child: const Text('Cancel')),
        if (_problem != null)
          TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(const _ImportResult(null)),
              child: const Text('Write it down instead')),
        FilledButton(
          onPressed: _busy ? null : _fetch,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_problem == null ? 'Fetch' : 'Try again'),
        ),
      ],
    );
  }
}

/// The sentence a failed fetch earns, by what actually went wrong. Never
/// the exception's own text: that is for the log.
@visibleForTesting
String importProblem(Object error) {
  if (error is FormatException) {
    return 'That doesn’t look like a web link. Paste one that starts '
        'with https://.';
  }
  if (error is TimeoutException) {
    return 'That page took too long to answer. Try again, or write the '
        'recipe down yourself.';
  }
  if (error is http.ClientException) {
    return 'That page didn’t answer. Check the link and your connection, '
        'or write the recipe down yourself.';
  }
  return ohFriendlyErrorMessage(error);
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

  /// What the form opened with, before any draft: the baseline a draft is
  /// measured against, and what Start over returns to.
  late final RecipeDraft _initial;
  late final RecipeDraftStore _drafts;

  /// True when the form opened on a kept draft rather than on [_initial].
  bool _resumed = false;

  /// Which draft this form keeps (lens audit humane-01): what is typed is
  /// written as it is typed, so leaving by any route (back, a tab, the app
  /// killed in the background) loses nothing.
  String get _draftKey => widget.existing != null
      ? 'edit:${widget.existing!.id}'
      : widget.imported != null
          ? 'import:${widget.imported!.sourceUrl}'
          : 'new';

  @override
  void initState() {
    super.initState();
    final imp = widget.imported;
    final ex = widget.existing;
    _initial = RecipeDraft(
      title: ex?.title ?? imp?.title ?? '',
      servings: (ex?.servings ?? imp?.servings)?.toString() ?? '',
      ingredients: ex != null
          ? ex.ingredients.map((i) => i.text).join('\n')
          : (imp?.ingredientLines.join('\n') ?? ''),
      instructions: ex?.instructions ?? imp?.instructions.join('\n\n') ?? '',
    );
    _drafts = ref.read(recipeDraftStoreProvider);
    final kept = _drafts.read(_draftKey);
    _resumed = kept != null && kept != _initial;
    final start = _resumed ? kept! : _initial;
    _title = TextEditingController(text: start.title);
    _servings = TextEditingController(text: start.servings);
    _ingredients = TextEditingController(text: start.ingredients);
    _instructions = TextEditingController(text: start.instructions);
    for (final c in [_title, _servings, _ingredients, _instructions]) {
      c.addListener(_keepDraft);
    }
  }

  RecipeDraft get _current => RecipeDraft(
        title: _title.text,
        servings: _servings.text,
        ingredients: _ingredients.text,
        instructions: _instructions.text,
      );

  void _keepDraft() {
    final now = _current;
    if (now == _initial) {
      _drafts.clear(_draftKey);
    } else {
      _drafts.write(_draftKey, now);
    }
  }

  void _startOver() {
    _title.text = _initial.title;
    _servings.text = _initial.servings;
    _ingredients.text = _initial.ingredients;
    _instructions.text = _initial.instructions;
    _drafts.clear(_draftKey);
    setState(() => _resumed = false);
  }

  @override
  void dispose() {
    for (final c in [_title, _servings, _ingredients, _instructions]) {
      c.dispose();
    }
    super.dispose();
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
      body: OhPage(
          padding: EdgeInsets.zero,
          // A form, not a feed: every field built up front, so the Save at
          // the foot can be scrolled to (and found by the 360dp sweep).
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isPreview)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'Here is what the page said: fix anything, then save.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.secondaryText(context)),
                      ),
                    ),
                  if (_resumed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Picked up where you left off.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          TextButton(
                            onPressed: _startOver,
                            child: const Text('Start over'),
                          ),
                        ],
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
                        labelText: 'Ingredients, one per line',
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
                  // Disabled until there is a title, with the reason in
                  // words (lens audit humane-10: it used to do nothing at
                  // all, silently). What is typed is kept as a draft either
                  // way, so leaving untitled loses nothing.
                  ListenableBuilder(
                    listenable: _title,
                    builder: (context, _) {
                      final hasTitle = _title.text.trim().isNotEmpty;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!hasTitle)
                            Padding(
                              padding:
                                  const EdgeInsets.only(bottom: AppSpacing.sm),
                              child: Text(
                                'Give the recipe a title to save it.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                        color:
                                            AppColors.secondaryText(context)),
                              ),
                            ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52)),
                            onPressed: hasTitle ? _save : null,
                            child: Text(widget.existing != null
                                ? 'Save changes'
                                : 'Save'),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ))),
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
    // Saved, so the draft has done its job.
    await _drafts.clear(_draftKey);
    if (mounted) Navigator.of(context).pop();
  }
}
