import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/add_sheet.dart';
import 'package:peckish/features/diary/presentation/targets_dialog.dart';
import 'package:peckish/features/diary/domain/suggestion_engine.dart';
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
            onPressed: () => context.push('/settings'),
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
            targets: targets.value ?? const DailyTargets(),
          ),
          if (!(targets.value?.isSet ?? true))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Set daily targets'),
                onPressed: () => showTargetsDialog(context, ref),
              ),
            ),
          if (ref.watch(_suggestionsProvider(today)) case final advice?
              when advice.status == SuggestionStatus.ideas ||
                  advice.status == SuggestionStatus.complete) ...[
            const SizedBox(height: AppSpacing.lg),
            _RoundOutCard(
              day: today,
              advice: advice,
              targets: targets.value ?? const DailyTargets(),
            ),
          ],
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
/// Live view of the persistent regulars — reacts to hides/unhides made
/// anywhere (the Foods screen), not just to diary writes.
final _usagesProvider = StreamProvider.autoDispose((ref) => ref
    .watch(foodUsageRepositoryProvider)
    .watchAll()
    .map((all) => [for (final u in all.where((u) => !u.hidden)) u]));
final _recentsProvider = Provider.autoDispose((ref) => ref
    .watch(_usagesProvider)
    .whenData((us) => [for (final u in us.take(12)) u.asTemplateEntry()]));
final _targetsProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(targetsRepositoryProvider).watch());

/// The round-out-your-day advice, or null when the card has nothing to
/// show: feature off, dismissed for this day, or inputs still loading.
final _suggestionsProvider =
    Provider.autoDispose.family<DaySuggestions?, String>((ref, day) {
  final prefs = ref.watch(userPrefsProvider).valueOrNull;
  if (prefs == null || !prefs.suggestionsEnabled) return null;
  if (prefs.suggestionsDismissedDay == day) return null;
  final targets = ref.watch(_targetsProvider).valueOrNull;
  final totals = ref.watch(_totalsProvider(day)).valueOrNull;
  final usages = ref.watch(_usagesProvider).valueOrNull;
  if (targets == null || totals == null || usages == null) return null;
  return const SuggestionEngine()
      .suggest(targets: targets, eaten: totals, regulars: usages);
});

/// A target's role, worn on its sleeve: floors read as ≥, caps as ≤,
/// plain "about" targets stay bare numbers.
String _roleMark(TargetRole role) => switch (role) {
      TargetRole.about => '',
      TargetRole.atLeast => '≥',
      TargetRole.under => '≤',
    };

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.targets});

  final MacroSet totals;
  final DailyTargets targets;

  String _fmt(double? v) => v == null ? '0' : v.round().toString();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final kcalTarget = targets.values.kcal;
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
                    kcalTarget == null
                        ? 'kcal'
                        : 'of ${_roleMark(targets.resolvedKcalRole)}'
                            '${_fmt(kcalTarget)} kcal',
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
                    target: targets.values.proteinG,
                    role: targets.resolvedProteinRole,
                    color: AppColors.sage),
                _MacroChip(
                    label: 'Carbs',
                    value: totals.carbG,
                    target: targets.values.carbG,
                    role: targets.resolvedCarbRole,
                    color: AppColors.butter),
                _MacroChip(
                    label: 'Fat',
                    value: totals.fatG,
                    target: targets.values.fatG,
                    role: targets.resolvedFatRole,
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
    required this.role,
    required this.color,
  });

  final String label;
  final double? value;
  final double? target;
  final TargetRole role;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = value == null ? '—' : '${value!.round()}g';
    final suffix =
        target == null ? '' : ' / ${_roleMark(role)}${target!.round()}g';
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

/// "Round out your day" — the engine's advice, worn lightly. Ideas come
/// with a one-tap Log; a finished day gets one warm line; dismissal lasts
/// exactly one day. The card never scolds: when nothing helps, the engine
/// goes quiet and this widget is never even built.
class _RoundOutCard extends ConsumerWidget {
  const _RoundOutCard({
    required this.day,
    required this.advice,
    required this.targets,
  });

  final String day;
  final DaySuggestions advice;
  final DailyTargets targets;

  String _combo(Suggestion s) => [
        for (final i in s.items)
          '${i.count > 1 ? '${i.count} × ' : ''}${i.usage.label}'
      ].join(' + ');

  /// Where the day lands, told only in the axes the user actually set.
  String _landing(Suggestion s) {
    final parts = <String>[
      if (targets.values.kcal != null) '${(s.after.kcal ?? 0).round()} kcal',
      if (targets.values.proteinG != null)
        '${(s.after.proteinG ?? 0).round()}g protein',
      if (targets.values.carbG != null)
        '${(s.after.carbG ?? 0).round()}g carbs',
      if (targets.values.fatG != null) '${(s.after.fatG ?? 0).round()}g fat',
    ];
    final where = parts.join(' · ');
    return s.completesDay ? 'Finishes the day: $where' : 'Closer: $where';
  }

  Future<void> _log(WidgetRef ref, Suggestion s) async {
    final diary = ref.read(diaryRepositoryProvider);
    for (final item in s.items) {
      final now = DateTime.now();
      final u = item.usage;
      await diary.log(DiaryEntry(
        id: const Uuid().v4(),
        day: DiaryEntry.dayOf(now),
        at: now,
        food: u.food,
        label: u.label,
        qty: u.qty * item.count,
        unitLabel: u.unitLabel,
        grams: u.grams == null ? null : u.grams! * item.count,
        macros: u.macros * item.count.toDouble(),
        source: EntrySource.tap,
        createdAt: now,
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dismiss = IconButton(
      icon: const Icon(Icons.close, size: 18),
      tooltip: 'Hide for today',
      onPressed: () =>
          ref.read(settingsRepositoryProvider).setSuggestionsDismissedDay(day),
    );

    if (advice.status == SuggestionStatus.complete) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 20, color: AppColors.sage),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text("You're set for today — every target met.",
                    style: theme.textTheme.bodyMedium),
              ),
              dismiss,
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Round out your day',
                      style: theme.textTheme.titleMedium),
                ),
                dismiss,
              ],
            ),
            for (final s in advice.ideas)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_combo(s), style: theme.textTheme.bodyLarge),
                        Text(
                          _landing(s),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.stone),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _log(ref, s),
                    child: const Text('Log'),
                  ),
                ],
              ),
          ],
        ),
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
