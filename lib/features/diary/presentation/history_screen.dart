import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/add_sheet.dart';
import 'package:peckish/features/diary/presentation/day_format.dart';
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
            _Chart(week: week, totals: totals, targets: targets),
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

/// The week, one macro at a time: a segmented axis picker over seven
/// tappable bars (each opens its day), value labels riding the bars, and
/// the selected axis's target drawn as a line wearing its role mark.
/// Still plain boxes — theme-aware, nothing to configure, nothing to
/// bloat.
class _Chart extends StatefulWidget {
  const _Chart(
      {required this.week, required this.totals, required this.targets});

  final List<String> week; // newest first
  final Map<String, MacroSet> totals;
  final DailyTargets targets;

  @override
  State<_Chart> createState() => _ChartState();
}

class _ChartState extends State<_Chart> {
  /// Selected axis, by [DailyTargets.axes]' own name — the chart hand-
  /// matches no field lists of its own.
  String _axis = 'kcal';

  TargetAxis get _selected =>
      widget.targets.axes.firstWhere((a) => a.axis == _axis);

  /// The picker speaks Title Case for the macros; 'kcal' is its own name.
  static String _label(String axis) =>
      axis == 'kcal' ? axis : axis[0].toUpperCase() + axis.substring(1);

  double? _of(MacroSet? m) => m == null ? null : _selected.of(m);

  /// '1.8k' for four-digit kcal, plain rounds otherwise — a label, not a
  /// spreadsheet cell.
  String _fmt(double v) => _axis == 'kcal' && v >= 1000
      ? '${(v / 1000).toStringAsFixed(1)}k'
      : v.round().toString();

  /// Vertical room reserved above a full-height bar for its value label.
  /// Labels live OUTSIDE the bars' frame so they never steal bar height —
  /// that theft is what once drew an at-target day below its own line.
  static const _labelBand = 18.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ordered = widget.week.reversed.toList();
    final axis = _selected;
    final target = axis.target;
    var scale = target ?? 0;
    for (final d in ordered) {
      final v = _of(widget.totals[d]) ?? 0;
      if (v > scale) scale = v;
    }
    if (scale <= 0) scale = 1;
    final ceiling = scale * 1.15;
    final unit = _axis == 'kcal' ? ' kcal' : 'g $_axis';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Scale-down beats wrapping here: at large text scales on narrow
        // phones the four segments would fold their labels mid-word into
        // tall broken columns (the fleet's recurring overflow shape).
        // FittedBox keeps one readable, tappable row.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: SegmentedButton<String>(
            segments: [
              for (final a in widget.targets.axes)
                ButtonSegment(value: a.axis, label: Text(_label(a.axis))),
            ],
            selected: {_axis},
            showSelectedIcon: false,
            style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            onSelectionChanged: (s) => setState(() => _axis = s.first),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 160,
          child: LayoutBuilder(builder: (context, constraints) {
            // ONE coordinate frame for bars and line: both are measured
            // against [usable] — the frame minus the label band — so a day
            // logged exactly at target sits exactly on the target line.
            final usable = constraints.maxHeight - _labelBand;
            return Stack(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in ordered)
                      _bar(context, theme, d, ceiling, usable),
                  ],
                ),
                if (target != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: (target / ceiling).clamp(0.0, 1.0) * usable,
                    child: Container(
                        key: const ValueKey('target-line'),
                        height: 1.5,
                        color: AppColors.stone),
                  ),
              ],
            );
          }),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final d in ordered)
              Expanded(
                child: Text(
                  weekdayLetters[DateTime.parse(d).weekday - 1],
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.stone),
                ),
              ),
          ],
        ),
        if (target != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              '${axis.role.mark}${target.round()}$unit target',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: AppColors.stone),
            ),
          ),
      ],
    );
  }

  Widget _bar(BuildContext context, ThemeData theme, String day,
      double ceiling, double usable) {
    final value = _of(widget.totals[day]);
    final fraction = ((value ?? 0) / ceiling).clamp(0.0, 1.0);
    // Bar height in the shared frame — the same pixels-per-unit the target
    // line uses, so at-target days genuinely touch it.
    final barHeight = fraction * usable;
    final isToday = day == widget.week.first;
    return Expanded(
      child: InkWell(
        key: ValueKey('bar-$day'),
        onTap: () => context.push('/history/$day'),
        child: Stack(
          children: [
            Positioned(
              left: 3,
              right: 3,
              bottom: 0,
              height: barHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: isToday
                      ? AppColors.paprika
                      : AppColors.paprika.withValues(alpha: 0.45),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ),
            ),
            if (value != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: barHeight + 2,
                child: Text(_fmt(value),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.stone)),
              ),
          ],
        ),
      ),
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
      title: Text(day == anchorDay ? 'Today' : prettyDay(day)),
      trailing: Text(
        kcal == null ? '—' : '${kcal.round()} kcal',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: kcal == null ? AppColors.stone : AppColors.paprika),
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
      appBar: AppBar(title: Text(prettyDay(day))),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add food to this day',
        onPressed: () => showAddSheet(context, day: day),
        child: const Icon(Icons.add),
      ),
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
