import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/entry_tile.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// History — the answer to "what happens to today, tomorrow?": nothing
/// disappears. Seven bars for the week, honest averages over the days
/// that were actually logged, and a fortnight of day rows where a blank
/// day stays a visible blank (never a fake zero). Calm by construction:
/// no streaks, no red, no judgement — the ledger, drawn.
class HistoryScreen extends ConsumerWidget {
  HistoryScreen({super.key, String? anchorDay})
      : anchorDay = anchorDay ?? DiaryEntry.dayOf(DateTime.now());

  /// The newest day shown ('YYYY-MM-DD') — today in production; tests pin it.
  final String anchorDay;

  static const _daysShown = 14;

  List<String> get _days {
    final d = DateTime.parse(anchorDay);
    return [
      for (var i = 0; i < _daysShown; i++)
        DiaryEntry.dayOf(DateTime(d.year, d.month, d.day - i)),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final days = _days;
    final totals =
        ref.watch(_rangeProvider(anchorDay)).valueOrNull ?? const {};
    final targets =
        ref.watch(_targetsProvider).valueOrNull ?? const DailyTargets();
    final week = days.take(7).toList();
    final loggedWeek = [
      for (final d in week)
        if (totals[d] != null) totals[d]!
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (totals.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'Your week fills in as you log. Come back after a few '
                'plates.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.stone),
              ),
            )
          else ...[
            _WeekBars(week: week, totals: totals, targets: targets),
            const SizedBox(height: AppSpacing.sm),
            _WeekStats(logged: loggedWeek),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text('Day by day', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final day in days)
            _DayRow(day: day, totals: totals[day], anchorDay: anchorDay),
        ],
      ),
    );
  }
}

final _rangeProvider = StreamProvider.autoDispose
    .family<Map<String, MacroSet>, String>((ref, anchorDay) {
  final d = DateTime.parse(anchorDay);
  final days = [
    for (var i = 0; i < HistoryScreen._daysShown; i++)
      DiaryEntry.dayOf(DateTime(d.year, d.month, d.day - i)),
  ];
  return ref.watch(diaryRepositoryProvider).watchTotalsForDays(days);
});
final _targetsProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(targetsRepositoryProvider).watch());
final _dayEntriesProvider = StreamProvider.autoDispose
    .family((ref, String day) =>
        ref.watch(diaryRepositoryProvider).watchEntriesForDay(day));

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _pretty(String day) {
  final d = DateTime.parse(day);
  return '${_weekdayNames[d.weekday - 1]} · ${_monthNames[d.month - 1]} '
      '${d.day}';
}

/// Seven simple bars, oldest → newest, today accented. Plain boxes, not a
/// chart library: theme-aware, nothing to configure, nothing to bloat.
class _WeekBars extends StatelessWidget {
  const _WeekBars(
      {required this.week, required this.totals, required this.targets});

  final List<String> week; // newest first
  final Map<String, MacroSet> totals;
  final DailyTargets targets;

  @override
  Widget build(BuildContext context) {
    final ordered = week.reversed.toList();
    final target = targets.values.kcal;
    var scale = target ?? 0;
    for (final d in ordered) {
      final k = totals[d]?.kcal ?? 0;
      if (k > scale) scale = k;
    }
    if (scale <= 0) scale = 1;

    final targetFraction = target == null ? null : target / (scale * 1.1);
    final mark = switch (targets.resolvedKcalRole) {
      TargetRole.about => '',
      TargetRole.atLeast => '≥',
      TargetRole.under => '≤',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 120,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in ordered)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FractionallySizedBox(
                          heightFactor: ((totals[d]?.kcal ?? 0) /
                                  (scale * 1.1))
                              .clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: d == week.first
                                  ? AppColors.jam
                                  : AppColors.jam.withValues(alpha: 0.45),
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (targetFraction != null)
                Align(
                  alignment: Alignment(0, 1 - 2 * targetFraction.clamp(0.0, 1.0)),
                  child: Container(height: 1.5, color: AppColors.stone),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final d in ordered)
              Expanded(
                child: Text(
                  _weekdayLetters[DateTime.parse(d).weekday - 1],
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: AppColors.stone),
                ),
              ),
          ],
        ),
        if (target != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '$mark${target.round()} kcal target',
              textAlign: TextAlign.end,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: AppColors.stone),
            ),
          ),
      ],
    );
  }
}

/// Averages over the days that were actually logged — never diluted by
/// blank days, and each macro averaged only where it was known.
class _WeekStats extends StatelessWidget {
  const _WeekStats({required this.logged});

  final List<MacroSet> logged;

  @override
  Widget build(BuildContext context) {
    if (logged.isEmpty) return const SizedBox.shrink();
    double? avg(double? Function(MacroSet) of) {
      final known = [
        for (final m in logged)
          if (of(m) != null) of(m)!
      ];
      if (known.isEmpty) return null;
      return known.reduce((a, b) => a + b) / known.length;
    }

    final kcal = avg((m) => m.kcal);
    final protein = avg((m) => m.proteinG);
    final parts = [
      if (kcal != null) 'avg ${kcal.round()} kcal',
      if (protein != null) '${protein.round()}g protein',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      'This week: ${parts.join(' · ')} a day, over '
      '${logged.length} logged ${logged.length == 1 ? 'day' : 'days'}.',
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: AppColors.stone),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow(
      {required this.day, required this.totals, required this.anchorDay});

  final String day;
  final MacroSet? totals;
  final String anchorDay;

  @override
  Widget build(BuildContext context) {
    final kcal = totals?.kcal;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(day == anchorDay ? 'Today' : _pretty(day)),
      trailing: Text(
        kcal == null ? '—' : '${kcal.round()} kcal',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: kcal == null ? AppColors.stone : AppColors.jam),
      ),
      onTap: () => context.push('/history/$day'),
    );
  }
}

/// One past day, opened from the list: the plate as it was. Lines can
/// still be swiped away (the ledger is yours) — totals everywhere react.
class HistoryDayScreen extends ConsumerWidget {
  const HistoryDayScreen({super.key, required this.day});

  final String day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(_dayEntriesProvider(day)).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(_pretty(day))),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'Nothing logged this day.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.stone),
              ),
            )
          else
            for (final entry in entries) EntryTile(entry: entry),
        ],
      ),
    );
  }
}
