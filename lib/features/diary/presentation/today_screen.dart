import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/add_sheet.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// Today — the daily loop. Law: logging a regular costs ONE tap (the recents
/// rail); anything else is two (the + sheet). Totals are plain numbers
/// against optional static targets; a heavy day is information, not alarm.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DiaryEntry.dayOf(DateTime.now());
    final entries = ref.watch(_entriesProvider(today));
    final totals = ref.watch(_totalsProvider(today));
    final recents = ref.watch(_recentsProvider);
    final targets = ref.watch(_targetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add food',
        onPressed: () => showAddSheet(context),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _TotalsCard(
            totals: totals.value ?? const MacroSet(),
            targets: targets.value ?? const MacroSet(),
          ),
          const SizedBox(height: AppSpacing.lg),
          if ((recents.value ?? const []).isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text('Your regulars',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                TextButton(
                  onPressed: () => context.push('/foods'),
                  child: const Text('See all'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _RecentsRail(recents: recents.value!),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Logged today', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if ((entries.value ?? const []).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'Nothing yet. Tap a regular above, or + to add.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.stone),
              ),
            )
          else
            for (final entry in entries.value!) _EntryTile(entry: entry),
          const SizedBox(height: 96), // room above the FAB
        ],
      ),
    );
  }
}

final _entriesProvider = StreamProvider.autoDispose
    .family((ref, String day) =>
        ref.watch(diaryRepositoryProvider).watchEntriesForDay(day));
final _totalsProvider = StreamProvider.autoDispose.family(
    (ref, String day) =>
        ref.watch(diaryRepositoryProvider).watchTotalsForDay(day));
final _recentsProvider = FutureProvider.autoDispose((ref) {
  ref.watch(_entriesProvider(DiaryEntry.dayOf(DateTime.now())));
  return ref.watch(diaryRepositoryProvider).recents();
});
final _targetsProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(targetsRepositoryProvider).watch());

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.targets});

  final MacroSet totals;
  final MacroSet targets;

  String _fmt(double? v) => v == null ? '0' : v.round().toString();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    _fmt(totals.kcal),
                    style: text.displayMedium?.copyWith(
                      color: AppColors.jam,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    targets.kcal == null
                        ? 'kcal'
                        : 'of ${_fmt(targets.kcal)} kcal',
                    style:
                        text.titleMedium?.copyWith(color: AppColors.stone),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _MacroChip(
                    label: 'Protein',
                    value: totals.proteinG,
                    target: targets.proteinG,
                    color: AppColors.sage),
                _MacroChip(
                    label: 'Carbs',
                    value: totals.carbG,
                    target: targets.carbG,
                    color: AppColors.butter),
                _MacroChip(
                    label: 'Fat',
                    value: totals.fatG,
                    target: targets.fatG,
                    color: AppColors.clay),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  const _MacroChip({
    required this.label,
    required this.value,
    required this.target,
    required this.color,
  });

  final String label;
  final double? value;
  final double? target;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = value == null ? '—' : '${value!.round()}g';
    final suffix = target == null ? '' : ' / ${target!.round()}g';
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text('$label $v$suffix'),
      visualDensity: VisualDensity.comfortable,
    );
  }
}

class _RecentsRail extends ConsumerWidget {
  const _RecentsRail({required this.recents});

  final List<DiaryEntry> recents;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: recents.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final template = recents[i];
          return ActionChip(
            avatar: const Icon(Icons.replay, size: 18),
            label: Text(template.label, overflow: TextOverflow.ellipsis),
            labelPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            onPressed: () async {
              final now = DateTime.now();
              await ref.read(diaryRepositoryProvider).log(DiaryEntry(
                    id: const Uuid().v4(),
                    day: DiaryEntry.dayOf(now),
                    at: now,
                    food: template.food,
                    label: template.label,
                    qty: template.qty,
                    unitLabel: template.unitLabel,
                    grams: template.grams,
                    macros: template.macros,
                    source: EntrySource.tap,
                    createdAt: now,
                  ));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                      SnackBar(content: Text('Logged ${template.label}')));
              }
            },
          );
        },
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry});

  final DiaryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.clay,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(diaryRepositoryProvider).delete(entry.id),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: AppSpacing.sm,
        title: Text(entry.label),
        subtitle: Text(
          entry.qty == 1
              ? entry.unitLabel
              : '${entry.qty % 1 == 0 ? entry.qty.toInt() : entry.qty} × ${entry.unitLabel}',
        ),
        trailing: Text(
          entry.macros.kcal == null
              ? '—'
              : '${entry.macros.kcal!.round()} kcal',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.jam),
        ),
      ),
    );
  }
}
