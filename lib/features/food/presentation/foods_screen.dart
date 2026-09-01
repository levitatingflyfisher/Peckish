import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/day_stamp.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/diary/presentation/portion_picker.dart';
import 'package:peckish/features/diary/presentation/regulars_rail.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/food/domain/usda_food.dart';
import 'package:peckish/shared/extensions/qty_format.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/undo_host.dart';
import 'package:peckish/shared/widgets/num_field.dart';
import 'package:peckish/shared/widgets/input_modal.dart';

/// How many regulars show before "Show all" — a long-lived household's
/// regulars stream is unbounded ("hundreds" per the phone report); the cap
/// keeps the first screenful cheap without hiding anything for good.
const _regularsCap = 30;

/// Same debounce as the + sheet's own search — fast typing costs one
/// query, not one per keystroke.
const _searchDebounce = Duration(milliseconds: 250);

/// Foods — the single searchable surface behind every "See all". Regulars
/// (the persistent usage record), My Foods (household customs), and Saved
/// meals all live here honestly labelled by how each is actually sorted —
/// reality is three different orders, not one "not quite alphabetical"
/// list. A search box on top turns all three, plus the bundled USDA spine,
/// into one result list.
class FoodsScreen extends ConsumerStatefulWidget {
  const FoodsScreen({super.key, this.day});

  /// The day every tap here lands on — null means today.
  ///
  /// Reached from a past day's rail, this screen used to open with no day
  /// at all and quietly log to today: the exact thing the rail was built
  /// to stop, one screen further along.
  final String? day;

  @override
  ConsumerState<FoodsScreen> createState() => _FoodsScreenState();
}

class _FoodsScreenState extends ConsumerState<FoodsScreen> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Same shape as the + sheet's own field: clearing takes effect at once,
  /// everything else waits out the quiet period.
  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      ref.read(_queryProvider.notifier).state = '';
      return;
    }
    _debounce = Timer(_searchDebounce, () {
      if (mounted) ref.read(_queryProvider.notifier).state = q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(_queryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Foods')),
      body: OhPage(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search your foods (works offline)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _onChanged,
                ),
              ),
              Expanded(
                child: query.trim().isEmpty
                    ? _IdleFoods(day: widget.day)
                    : _SearchResults(day: widget.day),
              ),
            ],
          )),
    );
  }
}

/// The settled (debounced) search text. Module-private and autoDispose:
/// this screen is its only writer and watcher, so it resets to '' when the
/// screen closes.
final _queryProvider = StateProvider.autoDispose((_) => '');

final _visibleCappedProvider = StreamProvider.autoDispose((ref) =>
    ref.watch(foodUsageRepositoryProvider).watchVisible(limit: _regularsCap));
final _visibleAllProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(foodUsageRepositoryProvider).watchVisible());
final _hiddenProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(foodUsageRepositoryProvider).watchHidden());
final _customsProvider = FutureProvider.autoDispose((ref) =>
    ref.watch(customFoodRepositoryProvider).getAll(includeArchived: true));
final _mealsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(savedMealRepositoryProvider).getAll());

/// Log a saved meal to [day] and say so — the same one-tap confirmation
/// every other relog path uses.
Future<void> _logMeal(
    BuildContext context, WidgetRef ref, SavedMeal meal, String? day) async {
  final stamp = dayStamp(day);
  await ref
      .read(savedMealRepositoryProvider)
      .logMeal(meal.id, at: stamp.at, day: stamp.day);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text('Logged ${meal.name}')));
}

Widget _mealTile(
    BuildContext context, WidgetRef ref, SavedMeal meal, String? day) {
  final kcal = meal.totals.kcal;
  return ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.restaurant_outlined),
    title: Text(meal.name),
    subtitle: Text(kcal == null
        ? '${meal.items.length} items'
        : '${meal.items.length} items · ${kcal.round()} kcal'),
    onTap: () => _logMeal(context, ref, meal, day),
  );
}

/// What the screen shows before any search: the three sections, each
/// honest about how it's actually sorted. Which day a tap feeds is carried
/// silently — the + sheet says so out loud because you go there mid-add;
/// nobody visits Foods wondering that.
class _IdleFoods extends ConsumerStatefulWidget {
  const _IdleFoods({this.day});

  final String? day;

  @override
  ConsumerState<_IdleFoods> createState() => _IdleFoodsState();
}

class _IdleFoodsState extends ConsumerState<_IdleFoods> {
  bool _showAllRegulars = false;

  @override
  Widget build(BuildContext context) {
    final visible = ref
        .watch(_showAllRegulars ? _visibleAllProvider : _visibleCappedProvider);
    final hidden = ref.watch(_hiddenProvider);
    final customs = ref.watch(_customsProvider);
    final meals = ref.watch(_mealsProvider);
    final text = Theme.of(context).textTheme;

    final live = visible.value ?? const <FoodUsage>[];
    final hiddenList = hidden.value ?? const <FoodUsage>[];
    final activeCustoms =
        (customs.value ?? const <CustomFood>[]).where((c) => !c.archived);
    final archivedCustoms =
        (customs.value ?? const <CustomFood>[]).where((c) => c.archived);
    final mealList = meals.value ?? const <SavedMeal>[];

    final loaded = visible.hasValue &&
        hidden.hasValue &&
        customs.hasValue &&
        meals.hasValue;
    final empty = loaded &&
        live.isEmpty &&
        hiddenList.isEmpty &&
        (customs.value ?? const []).isEmpty &&
        mealList.isEmpty;

    // One flat item list — headers included — so ListView.builder below only
    // instantiates the tiles that are actually on screen. A long-lived
    // household accumulates hundreds of regulars; building them all in one
    // frame is the kind of jank this screen never needs.
    final items = <Widget>[
      if (live.isNotEmpty || hiddenList.isNotEmpty) ...[
        Text('Regulars, by last use', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'What you actually reach for. Deleting diary lines '
          'never clears this.',
          style:
              text.bodySmall?.copyWith(color: AppColors.secondaryText(context)),
        ),
        for (final u in live) _RegularTile(usage: u, day: widget.day),
        if (!_showAllRegulars && live.length >= _regularsCap)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showAllRegulars = true),
              child: const Text('Show all'),
            ),
          ),
        if (hiddenList.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Hidden regulars', style: text.titleSmall),
            children: [
              for (final u in hiddenList)
                _RegularTile(usage: u, isHidden: true, day: widget.day),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (activeCustoms.isNotEmpty || archivedCustoms.isNotEmpty) ...[
        Text('My Foods, A to Z', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Household-defined foods, per serving, yours to edit.',
          style:
              text.bodySmall?.copyWith(color: AppColors.secondaryText(context)),
        ),
        for (final c in activeCustoms) _CustomTile(food: c, day: widget.day),
        if (archivedCustoms.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Resting', style: text.titleSmall),
            children: [
              for (final c in archivedCustoms)
                _CustomTile(food: c, isArchived: true, day: widget.day),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (mealList.isNotEmpty) ...[
        Text('Saved meals', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        for (final m in mealList) _mealTile(context, ref, m, widget.day),
      ],
    ];

    return empty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'Log a few foods and they gather here: your regulars '
                'for one-tap relogging, and My Foods for the household '
                'staples you define.',
                textAlign: TextAlign.center,
                style: text.bodyMedium
                    ?.copyWith(color: AppColors.secondaryText(context)),
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: items.length,
            itemBuilder: (_, i) => items[i],
          );
  }
}

/// One evaluation per settled query, across all four sources — regulars,
/// My Foods, saved meals and the bundled USDA spine. A single provider
/// watching the query, not a per-query family, so a query change reloads
/// IN PLACE and the list never flickers empty between keystrokes.
final _searchProvider = FutureProvider.autoDispose((ref) async {
  final query = ref.watch(_queryProvider);
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return const (
      <FoodUsage>[],
      <CustomFood>[],
      <SavedMeal>[],
      <UsdaFood>[],
    );
  }
  final visible = await ref.watch(_visibleAllProvider.future);
  final customs = await ref.watch(_customsProvider.future);
  final meals = await ref.watch(_mealsProvider.future);
  return (
    visible.where((u) => u.label.toLowerCase().contains(needle)).toList(),
    customs
        .where((c) => !c.archived && c.name.toLowerCase().contains(needle))
        .toList(),
    meals.where((m) => m.name.toLowerCase().contains(needle)).toList(),
    await ref.watch(usdaFoodRepositoryProvider).search(query),
  );
});

class _SearchResults extends ConsumerWidget {
  const _SearchResults({this.day});

  final String? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spine = ref.watch(spineReadyProvider);
    final results = ref.watch(_searchProvider);
    final text = Theme.of(context).textTheme;
    if (spine.isLoading) {
      return const Center(child: Text('Setting the table, one moment…'));
    }
    final (regulars, customs, meals, usdaFoods) = results.value ??
        const (
          <FoodUsage>[],
          <CustomFood>[],
          <SavedMeal>[],
          <UsdaFood>[],
        );
    if (regulars.isEmpty &&
        customs.isEmpty &&
        meals.isEmpty &&
        usdaFoods.isEmpty &&
        !results.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Nothing found. Try fewer words.',
            style: text.bodyMedium
                ?.copyWith(color: AppColors.secondaryText(context)),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        for (final u in regulars) _RegularTile(usage: u, day: day),
        for (final c in customs) _CustomTile(food: c, day: day),
        for (final m in meals) _mealTile(context, ref, m, day),
        for (final f in usdaFoods)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(f.per100g.kcal == null
                ? 'per 100 g'
                : '${f.per100g.kcal!.round()} kcal per 100 g'),
            onTap: () => showPortionPicker(context, ref, f, day: day),
          ),
      ],
    );
  }
}

class _RegularTile extends ConsumerWidget {
  const _RegularTile({required this.usage, this.isHidden = false, this.day});

  final FoodUsage usage;
  final bool isHidden;
  final String? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = usage.macros.kcal;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(usage.label),
      subtitle: Text('${usage.useCount}× · ${usage.unitLabel}'
          '${kcal == null ? '' : ' · ${kcal.round()} kcal'}'),
      // Logging again is what this list is FOR — it should not cost a trip
      // through the overflow menu. The menu keeps the same action for
      // anyone who went looking there.
      onTap: isHidden
          ? null
          : () => logRegular(context, ref, usage.asTemplateEntry(), day: day),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (choice) async {
          switch (choice) {
            case 'log':
              await logRegular(context, ref, usage.asTemplateEntry(), day: day);
            case 'hide':
              await ref
                  .read(foodUsageRepositoryProvider)
                  .setHidden(usage.identityKey, hidden: true);
            case 'show':
              await ref
                  .read(foodUsageRepositoryProvider)
                  .setHidden(usage.identityKey, hidden: false);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'log', child: Text('Log it again')),
          if (isHidden)
            const PopupMenuItem(value: 'show', child: Text('Show again'))
          else
            const PopupMenuItem(value: 'hide', child: Text('Hide from rail')),
        ],
      ),
    );
  }
}

class _CustomTile extends ConsumerWidget {
  const _CustomTile({required this.food, this.isArchived = false, this.day});

  final CustomFood food;
  final bool isArchived;
  final String? day;

  /// One serving of this custom food, as the entry a relog is built from.
  /// The id/day/at placeholders are the template's — relogEntry stamps the
  /// real ones.
  DiaryEntry _asTemplate() => DiaryEntry(
        id: '',
        day: '',
        at: DateTime.now(),
        food: FoodRef.custom(food.id),
        label: food.name,
        qty: 1,
        unitLabel: food.servingLabel,
        grams: null,
        macros: food.perServing,
        source: EntrySource.tap,
        createdAt: DateTime.now(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = food.perServing.kcal;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.home_outlined, color: AppColors.paprika),
      title: Text(food.name),
      subtitle: Text(
          '${food.servingLabel}${kcal == null ? '' : ' · ${kcal.round()} kcal'}'),
      onTap: isArchived
          ? null
          : () => logRegular(context, ref, _asTemplate(), day: day),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (choice) async {
          final repo = ref.read(customFoodRepositoryProvider);
          switch (choice) {
            case 'log':
              await logRegular(context, ref, _asTemplate(), day: day);
            case 'edit':
              await showInputDialog<void>(
                context,
                builder: (_) => _EditFoodDialog(food: food),
              );
              ref.invalidate(_customsProvider);
            case 'rest':
              await repo.setArchived(food.id, archived: true);
              ref.invalidate(_customsProvider);
            case 'wake':
              await repo.setArchived(food.id, archived: false);
              ref.invalidate(_customsProvider);
            case 'delete':
              // Chosen from a menu, so deliberate: no dialog, a lasting
              // Undo. Past diary entries keep their numbers either way;
              // only the food definition goes.
              final undo = ref.read(undoControllerProvider);
              // The row (and its context) is gone by the time Undo is
              // tapped; the container is not.
              final container =
                  ProviderScope.containerOf(context, listen: false);
              await repo.delete(food.id);
              ref.invalidate(_customsProvider);
              undo.show(
                message: 'Deleted ${food.name}',
                onUndo: () async {
                  await repo.restore(food.id);
                  container.invalidate(_customsProvider);
                },
              );
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'log', child: Text('Log it again')),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (isArchived)
            const PopupMenuItem(value: 'wake', child: Text('Back to My Foods'))
          else
            const PopupMenuItem(value: 'rest', child: Text('Rest this food')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// Edit a custom food in place. History is safe either way — diary entries
/// carry their own snapshots.
class _EditFoodDialog extends ConsumerStatefulWidget {
  const _EditFoodDialog({required this.food});

  final CustomFood food;

  @override
  ConsumerState<_EditFoodDialog> createState() => _EditFoodDialogState();
}

class _EditFoodDialogState extends ConsumerState<_EditFoodDialog> {
  late final TextEditingController _name;
  late final TextEditingController _serving;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    _name = TextEditingController(text: f.name);
    _serving = TextEditingController(text: f.servingLabel);
    _kcal = TextEditingController(text: _fmt(f.perServing.kcal));
    _protein = TextEditingController(text: _fmt(f.perServing.proteinG));
    _carbs = TextEditingController(text: _fmt(f.perServing.carbG));
    _fat = TextEditingController(text: _fmt(f.perServing.fatG));
  }

  @override
  void dispose() {
    for (final c in [_name, _serving, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double? v) => v == null ? '' : formatQty(v);

  static double? _num(TextEditingController c) => parseFlexibleDouble(c.text);

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await ref.read(customFoodRepositoryProvider).update(widget.food.copyWith(
          name: name,
          servingLabel: _serving.text.trim().isEmpty
              ? widget.food.servingLabel
              : _serving.text.trim(),
          perServing: MacroSet(
            kcal: _num(_kcal),
            proteinG: _num(_protein),
            carbG: _num(_carbs),
            fatG: _num(_fat),
          ),
        ));
    if (mounted) Navigator.of(context).pop();
  }

  Widget _numField(TextEditingController c, String label) =>
      NumField(controller: c, label: label);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit food'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: _serving,
                decoration:
                    const InputDecoration(labelText: 'Serving (e.g. 1 bowl)')),
            _numField(_kcal, 'kcal'),
            _numField(_protein, 'Protein g'),
            _numField(_carbs, 'Carbs g'),
            _numField(_fat, 'Fat g'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
