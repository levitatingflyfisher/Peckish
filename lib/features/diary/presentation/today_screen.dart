import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/relog.dart';
import 'package:peckish/features/diary/presentation/add_sheet.dart';
import 'package:peckish/features/diary/presentation/entry_tile.dart';
import 'package:peckish/features/diary/presentation/regulars_rail.dart';
import 'package:peckish/features/diary/presentation/totals_card.dart';
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
    final targets = ref.watch(_targetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          // History lives on the nav bar now — the corner is for Settings
          // alone.
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
          TotalsCard(
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
          if (ref.watch(_suggestionsProvider(today)) case final advice?) ...[
            const SizedBox(height: AppSpacing.lg),
            _RoundOutCard(
              day: today,
              advice: advice,
              targets: targets.value ?? const DailyTargets(),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          // Aimed at no day in particular, which means today — the same
          // rail a past day gets, pointed at now.
          const RegularsRail(),
          const SizedBox(height: AppSpacing.lg),
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
            for (final entry in entries.value!) EntryTile(entry: entry),
          const SizedBox(height: 96), // room above the FAB
        ],
      ),
    );
  }
}

final _entriesProvider = StreamProvider.autoDispose
    .family((ref, String day) =>
        ref.watch(diaryRepositoryProvider).watchEntriesForDay(day));

/// Totals fold out of the already-watched entries — one drift watch serves
/// the totals card, the day list, and the suggestion engine. Seeded with
/// the all-null set (never zero): a kcal-only day keeps protein unknown.
final _totalsProvider = Provider.autoDispose
    .family<AsyncValue<MacroSet>, String>((ref, day) => ref
        .watch(_entriesProvider(day))
        .whenData((entries) =>
            entries.fold(const MacroSet(), (sum, e) => sum + e.macros)));

/// The engine's pool: the most-used visible regulars, capped in SQL at the
/// engine's own ceiling.
final _enginePoolProvider = StreamProvider.autoDispose((ref) => ref
    .watch(foodUsageRepositoryProvider)
    .watchTopUsed(limit: SuggestionEngine.maxRegulars));
final _targetsProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(targetsRepositoryProvider).watch());

/// The round-out-your-day advice, or null whenever the card should not
/// exist: feature off, dismissed for this day, inputs still loading, or
/// the engine with nothing worth saying (no targets, or quiet). This
/// provider is the single decider — the widget renders whatever non-null
/// advice arrives, no second guard.
final _suggestionsProvider =
    Provider.autoDispose.family<DaySuggestions?, String>((ref, day) {
  final prefs = ref.watch(userPrefsProvider).valueOrNull;
  if (prefs == null || !prefs.suggestionsEnabled) return null;
  if (prefs.suggestionsDismissedDay == day) return null;
  final targets = ref.watch(_targetsProvider).valueOrNull;
  final totals = ref.watch(_totalsProvider(day)).valueOrNull;
  final pool = ref.watch(_enginePoolProvider).valueOrNull;
  if (targets == null || totals == null || pool == null) return null;
  final advice = const SuggestionEngine()
      .suggest(targets: targets, eaten: totals, regulars: pool);
  return switch (advice.status) {
    SuggestionStatus.ideas || SuggestionStatus.complete => advice,
    _ => null,
  };
});

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
    // One stamp for the whole idea: a combo is one decision, even if the
    // loop below straddles a midnight.
    final now = DateTime.now();
    for (final item in s.items) {
      await diary.log(relogEntry(item.usage.asTemplateEntry(),
          day: day, count: item.count, now: now));
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
