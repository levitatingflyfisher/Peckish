import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/food/domain/usda_food.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// The + sheet: offline search over the bundled spine + custom foods, the
/// staples list, and a quick-add line. Two taps end to end.
Future<void> showAddSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddSheet(),
    );

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
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
              onChanged: (q) => setState(() => _query = q),
            ),
          ),
          Expanded(
            child: _query.trim().isEmpty
                ? _IdleSheet(scroll: scroll)
                : _Results(query: _query, scroll: scroll),
          ),
        ],
      ),
    );
  }
}

/// What the sheet shows before any search: staples first (the point of the
/// app), then quick add.
class _IdleSheet extends ConsumerWidget {
  const _IdleSheet({required this.scroll});

  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(_mealsProvider);
    // The AI tile only exists once a household configured a brain — the
    // shipped default has no key, no endpoint, and no tile.
    final aiReady =
        ref.watch(aiConfigProvider).value?.configured ?? false;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      children: [
        ListTile(
          leading: const Icon(Icons.bolt_outlined, color: AppColors.butter),
          title: const Text('Quick add'),
          subtitle: const Text('Just a name and numbers you know'),
          onTap: () => _showQuickAdd(context, ref),
        ),
        ListTile(
          leading: const Icon(Icons.qr_code_scanner, color: AppColors.sage),
          title: const Text('Scan a barcode'),
          subtitle: const Text('Packaged food — one scan, one lookup'),
          onTap: () {
            Navigator.of(context).pop();
            context.push('/scan');
          },
        ),
        if (aiReady)
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: AppColors.jam),
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
                final now = DateTime.now();
                await ref.read(savedMealRepositoryProvider).logMeal(meal.id,
                    at: now, day: DiaryEntry.dayOf(now));
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
  const _Results({required this.query, required this.scroll});

  final String query;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spine = ref.watch(spineReadyProvider);
    final results = ref.watch(_searchProvider(query));
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
            leading: const Icon(Icons.home_outlined, color: AppColors.jam),
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
    final now = DateTime.now();
    await ref.read(diaryRepositoryProvider).log(DiaryEntry(
          id: const Uuid().v4(),
          day: DiaryEntry.dayOf(now),
          at: now,
          food: FoodRef.custom(c.id),
          label: c.name,
          qty: 1,
          unitLabel: c.servingLabel,
          grams: null,
          macros: c.perServing,
          source: EntrySource.search,
          createdAt: now,
        ));
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _pickPortion(
      BuildContext context, WidgetRef ref, UsdaFood food) async {
    final portions = await ref.read(usdaFoodRepositoryProvider).portionsOf(food.fdcId);
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      builder: (_) => _PortionSheet(food: food, portions: portions),
    );
    if (context.mounted) Navigator.of(context).pop();
  }
}

final _searchProvider = FutureProvider.autoDispose
    .family((ref, String query) async => (
          (await ref.watch(customFoodRepositoryProvider).getAll())
              .where((c) =>
                  c.name.toLowerCase().contains(query.trim().toLowerCase()))
              .toList(),
          await ref.watch(usdaFoodRepositoryProvider).search(query),
        ));

class _PortionSheet extends ConsumerWidget {
  const _PortionSheet({required this.food, required this.portions});

  final UsdaFood food;
  final List<UsdaPortion> portions;

  Future<void> _log(BuildContext context, WidgetRef ref, String unitLabel,
      double grams) async {
    final now = DateTime.now();
    await ref.read(diaryRepositoryProvider).log(DiaryEntry(
          id: const Uuid().v4(),
          day: DiaryEntry.dayOf(now),
          at: now,
          food: FoodRef.usda(food.fdcId),
          label: food.name,
          qty: 1,
          unitLabel: unitLabel,
          grams: grams,
          macros: food.per100g.forGrams(grams).clamped(),
          source: EntrySource.search,
          createdAt: now,
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

Future<void> _showQuickAdd(BuildContext context, WidgetRef ref) async {
  final label = TextEditingController();
  final kcal = TextEditingController();
  final protein = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Quick add'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: label,
              decoration: const InputDecoration(labelText: 'What was it?')),
          TextField(
              controller: kcal,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'kcal')),
          TextField(
              controller: protein,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Protein g (optional)')),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final name = label.text.trim();
            if (name.isEmpty) return;
            final now = DateTime.now();
            await ref.read(diaryRepositoryProvider).log(DiaryEntry(
                  id: const Uuid().v4(),
                  day: DiaryEntry.dayOf(now),
                  at: now,
                  food: const FoodRef.quick(),
                  label: name,
                  qty: 1,
                  unitLabel: 'serving',
                  grams: null,
                  macros: MacroSet(
                    kcal: double.tryParse(kcal.text),
                    proteinG: double.tryParse(protein.text),
                  ),
                  source: EntrySource.manual,
                  createdAt: now,
                ));
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          },
          child: const Text('Log it'),
        ),
      ],
    ),
  );
  if (context.mounted) Navigator.of(context).pop();
}
