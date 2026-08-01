import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/day_stamp.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/usda_food.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// Pick a portion of a raw USDA spine food and log it to [day] (null =
/// today). The one door onto a spine row — the + sheet's search and the
/// Foods screen's search both open it, so there is one portion picker in
/// the app, not two hand-built copies of the same sheet.
Future<void> showPortionPicker(
    BuildContext context, WidgetRef ref, UsdaFood food,
    {String? day}) async {
  final portions =
      await ref.read(usdaFoodRepositoryProvider).portionsOf(food.fdcId);
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    builder: (_) => _PortionSheet(food: food, portions: portions, day: day),
  );
}

class _PortionSheet extends ConsumerWidget {
  const _PortionSheet({required this.food, required this.portions, this.day});

  final UsdaFood food;
  final List<UsdaPortion> portions;
  final String? day;

  Future<void> _log(BuildContext context, WidgetRef ref, String unitLabel,
      double grams) async {
    final stamp = dayStamp(day);
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
