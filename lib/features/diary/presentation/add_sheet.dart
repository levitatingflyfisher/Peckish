import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/features/ai/on_device/plate_scanner.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/day_format.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/food/domain/usda_food.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/num_field.dart';

/// The + sheet: offline search over the bundled spine + custom foods, the
/// staples list, and a quick-add line. Two taps end to end. Pass [day] to
/// feed a PAST day (the history + button): the sheet says so, and the
/// now-flows (barcode, AI guess) stay off days that already happened.
Future<void> showAddSheet(BuildContext context, {String? day}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddSheet(day: day),
    );

/// Where a log for [targetDay] lands. Null = today, resolved AT LOG TIME
/// (a sheet left open across midnight logs to the real now); a past day
/// logs at that day's noon so it sorts naturally among real entries.
({String day, DateTime at}) _stamp(String? targetDay) {
  final now = DateTime.now();
  if (targetDay == null || targetDay == DiaryEntry.dayOf(now)) {
    return (day: DiaryEntry.dayOf(now), at: now);
  }
  return (day: targetDay, at: DateTime.parse('${targetDay}T12:00:00'));
}

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({this.day});

  /// Null = today; otherwise the past day this sheet feeds.
  final String? day;

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

/// How long the search field stays quiet after the last keystroke before
/// the query actually runs — long enough that fast typing costs one query
/// instead of one per key, short enough to still feel instant.
const _searchDebounce = Duration(milliseconds: 250);

class _AddSheetState extends ConsumerState<_AddSheet> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Keystrokes land in [_queryProvider] debounced. Clearing the field takes
  /// effect immediately (straight back to the staples, no lag); everything
  /// else waits out the quiet period.
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
    // Watched from the sheet itself — not from _Results — so the customs
    // cache lives exactly as long as one sheet open: read the table once,
    // then filter in memory on every keystroke.
    ref.watch(_customsProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search foods — works offline',
                border: OutlineInputBorder(),
              ),
              onChanged: _onChanged,
            ),
          ),
          Expanded(
            child: query.trim().isEmpty
                ? _IdleSheet(scroll: scroll, day: widget.day)
                : _Results(scroll: scroll, day: widget.day),
          ),
        ],
      ),
    );
  }
}

/// What the sheet shows before any search: staples first (the point of the
/// app), then quick add.
class _IdleSheet extends ConsumerWidget {
  const _IdleSheet({required this.scroll, this.day});

  final ScrollController scroll;
  final String? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(_mealsProvider);
    // The tile exists once a household configured a brain — OR on a device
    // that can label a plate photo (the zero-download CV rung needs no
    // opt-in: classifier + bundled spine, nothing leaves the phone).
    // valueOrNull, not value: a failed secure-storage read means "no
    // brain", never a crashed sheet (AsyncError.value rethrows).
    final aiReady =
        (ref.watch(aiConfigProvider).valueOrNull?.configured ?? false) ||
            (plateScanSupported &&
                ref.watch(plateScannerProvider) != null);
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        if (day != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('Adding to ${prettyDay(day!)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: AppColors.paprika)),
          ),
        ListTile(
          leading: const Icon(Icons.bolt_outlined, color: AppColors.butter),
          title: const Text('Quick add'),
          subtitle: const Text('Just a name and numbers you know'),
          onTap: () => _showQuickAdd(context, ref, day: day),
        ),
        if (day == null)
          ListTile(
            leading: const Icon(Icons.qr_code_scanner, color: AppColors.sage),
            title: const Text('Scan a barcode'),
            subtitle: const Text('Packaged food — one scan, one lookup'),
            onTap: () {
              Navigator.of(context).pop();
              context.push('/scan');
            },
          ),
        if (aiReady && day == null)
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: AppColors.paprika),
            title: const Text('Guess it for me'),
            subtitle: const Text('Describe the meal — AI drafts, you confirm'),
            onTap: () {
              Navigator.of(context).pop();
              showGuessSheet(context);
            },
          ),
        const Divider(),
        if ((meals.value ?? const []).isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('Saved meals',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final meal in meals.value!)
            ListTile(
              leading: const Icon(Icons.restaurant_outlined),
              title: Text(meal.name),
              subtitle: Text(meal.totals.kcal == null
                  ? '${meal.items.length} items'
                  : '${meal.items.length} items · ${meal.totals.kcal!.round()} kcal'),
              onTap: () async {
                final stamp = _stamp(day);
                await ref.read(savedMealRepositoryProvider).logMeal(meal.id,
                    at: stamp.at, day: stamp.day);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ],
    );
  }
}

final _mealsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(savedMealRepositoryProvider).getAll());

class _Results extends ConsumerWidget {
  const _Results({required this.scroll, this.day});

  final ScrollController scroll;
  final String? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spine = ref.watch(spineReadyProvider);
    final results = ref.watch(_searchProvider);
    if (spine.isLoading) {
      return const Center(child: Text('Setting the table — one moment…'));
    }
    final customs = results.value?.$1 ?? const <CustomFood>[];
    final foods = results.value?.$2 ?? const <UsdaFood>[];
    if (customs.isEmpty && foods.isEmpty && !results.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Nothing found. Try fewer words, or use Quick add.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.stone),
          ),
        ),
      );
    }
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        for (final c in customs)
          ListTile(
            leading: const Icon(Icons.home_outlined, color: AppColors.paprika),
            title: Text(c.name),
            subtitle: Text(
                '${c.servingLabel}${c.perServing.kcal == null ? '' : ' · ${c.perServing.kcal!.round()} kcal'}'),
            onTap: () => _logCustom(context, ref, c),
          ),
        for (final f in foods)
          ListTile(
            title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(f.per100g.kcal == null
                ? 'per 100 g'
                : '${f.per100g.kcal!.round()} kcal per 100 g'),
            onTap: () => _pickPortion(context, ref, f),
          ),
      ],
    );
  }

  Future<void> _logCustom(
      BuildContext context, WidgetRef ref, CustomFood c) async {
    final stamp = _stamp(day);
    await ref.read(diaryRepositoryProvider).log(DiaryEntry(
          id: const Uuid().v4(),
          day: stamp.day,
          at: stamp.at,
          food: FoodRef.custom(c.id),
          label: c.name,
          qty: 1,
          unitLabel: c.servingLabel,
          grams: null,
          macros: c.perServing,
          source: EntrySource.search,
          createdAt: DateTime.now(),
        ));
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _pickPortion(
      BuildContext context, WidgetRef ref, UsdaFood food) async {
    final portions = await ref.read(usdaFoodRepositoryProvider).portionsOf(food.fdcId);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (_) => _PortionSheet(food: food, portions: portions, day: day),
    );
    if (context.mounted) Navigator.of(context).pop();
  }
}

/// The settled (debounced) search text. Module-private and autoDispose: the
/// sheet is its only writer and watcher, so it resets to '' when the sheet
/// closes.
final _queryProvider = StateProvider.autoDispose((_) => '');

/// The custom-foods table, read ONCE per sheet open (the sheet state keeps
/// this alive for its whole lifetime). Per-keystroke filtering happens in
/// memory in [_searchProvider] — the table is never re-read while typing.
final _customsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(customFoodRepositoryProvider).getAll());

/// One evaluation per settled query. A single provider watching the query —
/// not a per-query family — so a query change reloads IN PLACE: AsyncValue
/// carries the previous results through the reload and the list never
/// flickers empty between keystrokes.
final _searchProvider = FutureProvider.autoDispose((ref) async {
  final query = ref.watch(_queryProvider);
  final needle = query.trim().toLowerCase();
  return (
    (await ref.watch(_customsProvider.future))
        .where((c) => c.name.toLowerCase().contains(needle))
        .toList(),
    await ref.watch(usdaFoodRepositoryProvider).search(query),
  );
});

class _PortionSheet extends ConsumerWidget {
  const _PortionSheet(
      {required this.food, required this.portions, this.day});

  final UsdaFood food;
  final List<UsdaPortion> portions;
  final String? day;

  Future<void> _log(BuildContext context, WidgetRef ref, String unitLabel,
      double grams) async {
    final stamp = _stamp(day);
    await ref.read(diaryRepositoryProvider).log(DiaryEntry(
          id: const Uuid().v4(),
          day: stamp.day,
          at: stamp.at,
          food: FoodRef.usda(food.fdcId),
          label: food.name,
          qty: 1,
          unitLabel: unitLabel,
          grams: grams,
          macros: food.per100g.forGrams(grams).clamped(),
          source: EntrySource.search,
          createdAt: DateTime.now(),
        ));
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(food.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final p in portions)
            ListTile(
              title: Text(p.label),
              trailing: Text(food.per100g.kcal == null
                  ? '${p.grams.round()} g'
                  : '${(food.per100g.kcal! * p.grams / 100).round()} kcal'),
              onTap: () => _log(context, ref, p.label, p.grams),
            ),
          ListTile(
            title: const Text('100 g'),
            trailing: Text(food.per100g.kcal == null
                ? ''
                : '${food.per100g.kcal!.round()} kcal'),
            onTap: () => _log(context, ref, '100 g', 100),
          ),
        ],
      ),
    );
  }
}

Future<void> _showQuickAdd(BuildContext context, WidgetRef ref,
    {String? day}) async {
  // Pops with true only when a line was logged — Cancel returns to the +
  // sheet instead of closing it (the sheet is where you'd try again).
  final logged = await showDialog<bool>(
    context: context,
    builder: (_) => _QuickAddDialog(day: day),
  );
  if (logged == true && context.mounted) Navigator.of(context).pop();
}

/// Quick add: a name plus any of the four numbers you know — every macro is
/// enterable, none is required. "Remember this food" turns the one-off line
/// into a custom food so search (and My Foods) finds it next time.
class _QuickAddDialog extends ConsumerStatefulWidget {
  const _QuickAddDialog({this.day});

  final String? day;

  @override
  ConsumerState<_QuickAddDialog> createState() => _QuickAddDialogState();
}

class _QuickAddDialogState extends ConsumerState<_QuickAddDialog> {
  final _label = TextEditingController();
  final _kcal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  bool _remember = false;

  /// A double-tapped Log it must land ONE line — the second pop would
  /// otherwise cascade past the + sheet into whatever is beneath it.
  bool _saving = false;

  @override
  void dispose() {
    _label.dispose();
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  static double? _num(TextEditingController c) =>
      parseFlexibleDouble(c.text);

  Widget _numField(TextEditingController c, String label) =>
      NumField(controller: c, label: label);

  Future<void> _log() async {
    final name = _label.text.trim();
    if (name.isEmpty || _saving) return;
    _saving = true;
    final now = DateTime.now();
    final macros = MacroSet(
      kcal: _num(_kcal),
      proteinG: _num(_protein),
      carbG: _num(_carbs),
      fatG: _num(_fat),
    );

    var food = const FoodRef.quick();
    if (_remember) {
      final id = const Uuid().v4();
      await ref.read(customFoodRepositoryProvider).create(CustomFood(
            id: id,
            name: name,
            servingLabel: 'serving',
            perServing: macros,
            createdAt: now,
          ));
      food = FoodRef.custom(id);
    }

    final stamp = _stamp(widget.day);
    await ref.read(diaryRepositoryProvider).log(DiaryEntry(
          id: const Uuid().v4(),
          day: stamp.day,
          at: stamp.at,
          food: food,
          label: name,
          qty: 1,
          unitLabel: 'serving',
          grams: null,
          macros: macros,
          source: EntrySource.manual,
          createdAt: now,
        ));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quick add'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _label,
                decoration:
                    const InputDecoration(labelText: 'What was it?')),
            _numField(_kcal, 'kcal'),
            _numField(_protein, 'Protein g'),
            _numField(_carbs, 'Carbs g'),
            _numField(_fat, 'Fat g'),
            const SizedBox(height: AppSpacing.sm),
            CheckboxListTile(
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Remember this food'),
              subtitle: const Text('Shows up in search next time'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(onPressed: _log, child: const Text('Log it')),
      ],
    );
  }
}
