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
/// disappears. A month at a time: the trend line for the axis you picked
/// with your target drawn across it, honest averages over the days you
/// actually logged, and a calendar where **every past day opens its own
/// plate**. Calm by construction: no streaks, no red, no judgement.
///
/// The calendar is deliberately the edit surface and says so in words —
/// the v0.7 phone test found people never guessed that the chart page was
/// where you fix a missed day.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, this.today});

  /// Pinned by tests ('YYYY-MM-DD'); production reads the real clock.
  final String? today;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late final String _today = widget.today ?? DiaryEntry.dayOf(DateTime.now());

  /// The visible month, as its first day.
  late DateTime _month = _firstOfMonthOf(_today);

  /// Selected axis, by [DailyTargets.axes]' own name — shared by the trend
  /// line and the calendar so one tap re-reads the whole month.
  String _axis = 'kcal';

  static DateTime _firstOfMonthOf(String day) {
    final d = DateTime.parse(day);
    return DateTime(d.year, d.month);
  }

  String get _monthKey =>
      '${_month.year.toString().padLeft(4, '0')}-'
      '${_month.month.toString().padLeft(2, '0')}';

  /// True once the visible month contains today — there is no forward from
  /// the month you are living in.
  bool get _atCurrentMonth => !_month.isBefore(_firstOfMonthOf(_today));

  void _step(int months) => setState(() =>
      _month = DateTime(_month.year, _month.month + months));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals =
        ref.watch(_monthProvider(_monthKey)).valueOrNull ?? const {};
    final targets =
        ref.watch(_targetsProvider).valueOrNull ?? const DailyTargets();
    final axis = targets.axes.firstWhere((a) => a.axis == _axis);
    // Days already lived: the trend line must not trail off into a month's
    // unlived remainder.
    final days = [
      for (final d in monthDays(_month))
        if (d.compareTo(_today) <= 0) d
    ];
    final logged = [
      for (final d in days)
        if (totals[d] != null) totals[d]!
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _MonthBar(
            label: '${monthFullNames[_month.month - 1]} ${_month.year}',
            onPrev: () => _step(-1),
            onNext: _atCurrentMonth ? null : () => _step(1),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Scale-down beats wrapping: at large text scales on narrow
          // phones the four segments would fold their labels mid-word into
          // tall broken columns (the fleet's recurring overflow shape).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: SegmentedButton<String>(
              segments: [
                for (final a in targets.axes)
                  ButtonSegment(value: a.axis, label: Text(_axisLabel(a.axis))),
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
          if (logged.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                'Your month fills in as you log. Come back after a few '
                'plates.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.stone),
              ),
            )
          else ...[
            _TrendChart(days: days, totals: totals, axis: axis),
            if (axis.target != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  '${axis.role.mark}${axis.target!.round()}'
                  '${_axis == 'kcal' ? ' kcal' : 'g $_axis'} target',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.stone),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            _MonthStats(logged: logged),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text('Tap any day to add to it or fix it',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _Calendar(
            month: _month,
            today: _today,
            totals: totals,
            axis: axis,
          ),
        ],
      ),
    );
  }

  /// The picker speaks Title Case for the macros; 'kcal' is its own name.
  static String _axisLabel(String axis) =>
      axis == 'kcal' ? axis : axis[0].toUpperCase() + axis.substring(1);
}

/// Every day key in [month], first to last.
List<String> monthDays(DateTime month) {
  final last = DateTime(month.year, month.month + 1, 0).day;
  return [
    for (var i = 1; i <= last; i++)
      DiaryEntry.dayOf(DateTime(month.year, month.month, i)),
  ];
}

final _monthProvider = StreamProvider.autoDispose
    .family<Map<String, MacroSet>, String>((ref, monthKey) {
  final days = monthDays(DateTime.parse('$monthKey-01'));
  return ref.watch(diaryRepositoryProvider).watchTotalsForDays(days);
});
final _targetsProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(targetsRepositoryProvider).watch());
final _dayEntriesProvider = StreamProvider.autoDispose
    .family((ref, String day) =>
        ref.watch(diaryRepositoryProvider).watchEntriesForDay(day));

/// '‹  August 2026  ›' — forward is null at the current month.
class _MonthBar extends StatelessWidget {
  const _MonthBar(
      {required this.label, required this.onPrev, required this.onNext});

  final String label;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const ValueKey('month-prev'),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: onPrev,
          ),
          Flexible(
            child: Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            key: const ValueKey('month-next'),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: onNext,
          ),
        ],
      );
}

/// The month as one line: a dot per logged day, connected where days are
/// consecutive and BROKEN where they aren't — a gap is a day you didn't
/// log, never a zero. The target rides across as a single rule, and both
/// live in one coordinate frame so an at-target day sits exactly on it.
class _TrendChart extends StatelessWidget {
  const _TrendChart(
      {required this.days, required this.totals, required this.axis});

  final List<String> days; // ascending, already lived
  final Map<String, MacroSet> totals;
  final TargetAxis axis;

  static const _height = 150.0;
  static const _leftPad = 34.0;
  static const _dot = 7.0;

  @override
  Widget build(BuildContext context) {
    final target = axis.target;
    var scale = target ?? 0;
    for (final d in days) {
      final v = _valueOf(d);
      if (v != null && v > scale) scale = v;
    }
    if (scale <= 0) scale = 1;
    final ceiling = scale * 1.15;

    return SizedBox(
      height: _height,
      child: LayoutBuilder(builder: (context, constraints) {
        final chartW = constraints.maxWidth - _leftPad;
        final h = constraints.maxHeight;
        double xOf(int i) => days.length == 1
            ? _leftPad + chartW / 2
            : _leftPad + (i / (days.length - 1)) * chartW;
        // Height ABOVE the floor, so every element below shares one frame.
        double liftOf(double v) => (v / ceiling).clamp(0.0, 1.0) * h;

        final points = <(int, double)>[
          for (final (i, d) in days.indexed)
            if (_valueOf(d) != null) (i, _valueOf(d)!),
        ];

        return Stack(
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              size: Size(constraints.maxWidth, h),
              painter: _TrendPainter(
                offsets: [
                  for (final (i, v) in points)
                    (index: i, offset: Offset(xOf(i), h - liftOf(v))),
                ],
                ceiling: ceiling,
                compact: _compact,
                lineColor: AppColors.paprika,
                // The canvas labels borrow the app's own type — a bare
                // TextStyle would fall back to the platform default and
                // read as a different font from every Text beside it.
                labelStyle: (Theme.of(context).textTheme.labelSmall ??
                        const TextStyle())
                    .copyWith(color: AppColors.stone, fontSize: 9),
              ),
            ),
            if (target != null)
              Positioned(
                left: _leftPad,
                right: 0,
                bottom: liftOf(target),
                child: Container(
                    key: const ValueKey('target-line'),
                    height: 1.5,
                    color: AppColors.stone),
              ),
            for (final (i, v) in points)
              Positioned(
                left: xOf(i) - _dot / 2,
                bottom: liftOf(v) - _dot / 2,
                width: _dot,
                height: _dot,
                child: DecoratedBox(
                  key: ValueKey('point-${days[i]}'),
                  decoration: const BoxDecoration(
                      color: AppColors.paprika, shape: BoxShape.circle),
                ),
              ),
            // The zero line, named so the frame itself is testable.
            Positioned(
              left: _leftPad,
              right: 0,
              bottom: 0,
              child: Container(
                  key: const ValueKey('chart-floor'),
                  height: 1,
                  color: Colors.transparent),
            ),
          ],
        );
      }),
    );
  }

  double? _valueOf(String day) {
    final m = totals[day];
    return m == null ? null : axis.of(m);
  }

  /// '1.8k' for four-digit kcal, plain rounds otherwise — a label, not a
  /// spreadsheet cell.
  String _compact(double v) => axis.axis == 'kcal' && v >= 1000
      ? '${(v / 1000).toStringAsFixed(1)}k'
      : v.round().toString();
}

typedef _Pt = ({int index, Offset offset});

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.offsets,
    required this.ceiling,
    required this.compact,
    required this.lineColor,
    required this.labelStyle,
  });

  final List<_Pt> offsets;
  final double ceiling;
  final String Function(double) compact;
  final Color lineColor;
  final TextStyle labelStyle;

  static const _leftPad = _TrendChart._leftPad;

  @override
  void paint(Canvas canvas, Size size) {
    // Three grid lines with their values — the axis, without a whole axis.
    for (final frac in const [0.0, 0.5, 1.0]) {
      final y = size.height * (1 - frac);
      canvas.drawLine(
        Offset(_leftPad, y),
        Offset(size.width, y),
        Paint()
          ..color = (labelStyle.color ?? lineColor).withValues(alpha: 0.25)
          ..strokeWidth = 0.5,
      );
      // The topmost label hangs BELOW its rule; above it would be clipped
      // off the top of the chart box.
      _label(canvas, compact(ceiling * frac), 0, frac == 1.0 ? y + 1 : y - 6);
    }

    // Consecutive calendar days join up; a gap in logging breaks the line
    // rather than drawing a slope through a day that never happened.
    for (final run in _runs()) {
      if (run.length < 2) continue;
      final path = Path()..moveTo(run.first.dx, run.first.dy);
      for (final p in run.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );

      final fill = Path()..moveTo(run.first.dx, size.height);
      for (final p in run) {
        fill.lineTo(p.dx, p.dy);
      }
      fill
        ..lineTo(run.last.dx, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withValues(alpha: 0.18),
              lineColor.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
  }

  List<List<Offset>> _runs() {
    final runs = <List<Offset>>[];
    for (var i = 0; i < offsets.length; i++) {
      final consecutive =
          i > 0 && offsets[i].index == offsets[i - 1].index + 1;
      if (consecutive) {
        runs.last.add(offsets[i].offset);
      } else {
        runs.add([offsets[i].offset]);
      }
    }
    return runs;
  }

  void _label(Canvas canvas, String text, double x, double y) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.offsets != offsets ||
      old.ceiling != ceiling ||
      old.labelStyle != labelStyle;
}

/// The month grid, Monday-first. Every past cell opens that day's plate;
/// the days you haven't lived yet are visible but inert — writing ahead is
/// the Plan tab's job, never History's.
class _Calendar extends StatelessWidget {
  const _Calendar(
      {required this.month,
      required this.today,
      required this.totals,
      required this.axis});

  final DateTime month;
  final String today;
  final Map<String, MacroSet> totals;
  final TargetAxis axis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = monthDays(month);
    // How full a cell reads: against the target when there is one, else
    // against the month's own biggest day.
    var ceiling = axis.target ?? 0;
    for (final d in days) {
      final v = _valueOf(d);
      if (v != null && v > ceiling) ceiling = v;
    }
    if (ceiling <= 0) ceiling = 1;
    final leading = DateTime.parse(days.first).weekday - 1; // Monday-first

    return Column(
      children: [
        Row(
          children: [
            for (final letter in weekdayLetters)
              Expanded(
                child: Text(letter,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.stone)),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < leading; i++) const SizedBox.shrink(),
            for (final day in days)
              _DayCell(
                key: ValueKey('day-$day'),
                day: day,
                value: _valueOf(day),
                fill: (_valueOf(day) ?? 0) / ceiling,
                isToday: day == today,
                isFuture: day.compareTo(today) > 0,
                compact: _compact,
              ),
          ],
        ),
      ],
    );
  }

  double? _valueOf(String day) {
    final m = totals[day];
    return m == null ? null : axis.of(m);
  }

  String _compact(double v) => axis.axis == 'kcal' && v >= 1000
      ? '${(v / 1000).toStringAsFixed(1)}k'
      : v.round().toString();
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.day,
    required this.value,
    required this.fill,
    required this.isToday,
    required this.isFuture,
    required this.compact,
  });

  final String day;
  final double? value;
  final double fill;
  final bool isToday;
  final bool isFuture;
  final String Function(double) compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = DateTime.parse(day).day.toString();
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isFuture ? null : () => context.push('/history/$day'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: value == null
                ? Colors.transparent
                : AppColors.paprika
                    .withValues(alpha: 0.12 + 0.45 * fill.clamp(0.0, 1.0)),
            border: isToday
                ? Border.all(color: AppColors.paprika, width: 1.5)
                : Border.all(color: AppColors.stone.withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(number,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: isFuture ? AppColors.stone : null)),
                    if (value != null)
                      Text(compact(value!),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: AppColors.paprika)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Averages over the days that were actually logged — never diluted by
/// blank days, and each macro averaged only where it was known.
class _MonthStats extends StatelessWidget {
  const _MonthStats({required this.logged});

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
      'This month: ${parts.join(' · ')} a day, over '
      '${logged.length} logged ${logged.length == 1 ? 'day' : 'days'}.',
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: AppColors.stone),
    );
  }
}

/// One past day, opened from the calendar: the plate as it was. Lines can
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
