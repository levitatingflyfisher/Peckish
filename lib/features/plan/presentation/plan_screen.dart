import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/plan/domain/week.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/input_modal.dart';
import 'package:peckish/shared/widgets/theme_toggle_action.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

/// The week — Peckish's signature surface. Each day is a plate: an empty ring
/// until dinner is planned, filled butter-warm once it is. "Leftovers" and
/// "Out" are one tap and fully first-class. "Set the table" turns the visible
/// week into the grocery list.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  /// Monday of the visible week.
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = mondayOf(DateTime.now());
  }

  List<String> get _days => weekDays(_weekStart);

  @override
  Widget build(BuildContext context) {
    // Keyed by the week-start DAY STRING, not the day list: a List is a new
    // instance every build, and a family provider keyed on it can never
    // match itself — an infinite rebuild loop (pumpAndSettle hangs forever).
    final entries = ref.watch(_weekProvider(_days.first));
    final byDay = <String, List<PlanEntry>>{};
    for (final e in entries.value ?? const <PlanEntry>[]) {
      byDay.putIfAbsent(e.day, () => []).add(e);
    }

    return Scaffold(
      // The tab's own name in the bar (lens audit dmmt-04: the bar held
      // only a date range), with room for the theme choice. The week
      // stepper moves into the page, pinned above the days the way
      // History pins its month bar.
      appBar: AppBar(
        title: const Text('Plan'),
        actions: const [OhBarActions(children: [ThemeToggleAction()])],
      ),
      body: OhPage(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      tooltip: 'Previous week',
                      onPressed: () => setState(() => _weekStart = DateTime(
                          _weekStart.year,
                          _weekStart.month,
                          _weekStart.day - 7)),
                    ),
                    Expanded(
                      child: Text(
                        _weekTitle(),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      tooltip: 'Next week',
                      onPressed: () => setState(() => _weekStart = DateTime(
                          _weekStart.year,
                          _weekStart.month,
                          _weekStart.day + 7)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    for (var i = 0; i < 7; i++)
                      _DayRow(
                        date: DateTime(_weekStart.year, _weekStart.month,
                            _weekStart.day + i),
                        day: _days[i],
                        entries: byDay[_days[i]] ?? const [],
                        onAdd: () => _showAddToDay(context, _days[i]),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
              // Pinned below the week, outside the scroll, in the thumb zone:
              // the app's central act was off the first screenful on every
              // phone (lens audit finding 3, dmmt-08).
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
                child: FilledButton.icon(
                  icon: const Icon(Icons.shopping_basket_outlined),
                  label: const Text('Set the table: build the grocery list'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () async {
                    await ref
                        .read(groceryRepositoryProvider)
                        .regenerateFromPlan(_days);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'Grocery list refilled from this week’s plan')));
                    }
                  },
                ),
              ),
            ],
          )),
    );
  }

  String _weekTitle() {
    final end = DateTime(_weekStart.year, _weekStart.month, _weekStart.day + 6);
    String md(DateTime d) => '${d.month}/${d.day}';
    return 'Week of ${md(_weekStart)}–${md(end)}';
  }

  Future<void> _showAddToDay(BuildContext context, String day) async {
    final recipes = await ref.read(recipeRepositoryProvider).getAll();
    final meals = await ref.read(savedMealRepositoryProvider).getAll();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Plan $day',
                style: Theme.of(sheetContext).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.replay, size: 18),
                  label: const Text('Leftovers'),
                  onPressed: () => _addNote(sheetContext, day, 'Leftovers'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.storefront_outlined, size: 18),
                  label: const Text('Out'),
                  onPressed: () => _addNote(sheetContext, day, 'Out'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Note…'),
                  onPressed: () async {
                    final controller = TextEditingController();
                    final note = await showInputDialog<String>(
                      sheetContext,
                      builder: (d) => AlertDialog(
                        title: const Text('Plan a note'),
                        content:
                            TextField(controller: controller, autofocus: true),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(d).pop(),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () =>
                                  Navigator.of(d).pop(controller.text.trim()),
                              child: const Text('Plan it')),
                        ],
                      ),
                    );
                    if (note != null &&
                        note.isNotEmpty &&
                        sheetContext.mounted) {
                      await _addNote(sheetContext, day, note);
                    }
                  },
                ),
              ],
            ),
            if (recipes.isNotEmpty) ...[
              const Divider(height: AppSpacing.xl),
              Text('From the recipe box',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              for (final r in recipes)
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: Text(r.title),
                  onTap: () =>
                      _addRef(sheetContext, day, PlanKind.recipe, r.id),
                ),
            ],
            if (meals.isNotEmpty) ...[
              const Divider(height: AppSpacing.xl),
              Text('Saved meals',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
              for (final m in meals)
                ListTile(
                  leading: const Icon(Icons.restaurant_outlined),
                  title: Text(m.name),
                  onTap: () => _addRef(sheetContext, day, PlanKind.meal, m.id),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addNote(BuildContext sheetContext, String day, String note) =>
      _upsert(
          sheetContext,
          PlanEntry(
            id: const Uuid().v4(),
            day: day,
            slot: PlanSlot.dinner,
            kind: PlanKind.note,
            note: note,
          ));

  Future<void> _addRef(
          BuildContext sheetContext, String day, PlanKind kind, String refId) =>
      _upsert(
          sheetContext,
          PlanEntry(
            id: const Uuid().v4(),
            day: day,
            slot: PlanSlot.dinner,
            kind: kind,
            refId: refId,
          ));

  Future<void> _upsert(BuildContext sheetContext, PlanEntry entry) async {
    await ref.read(planRepositoryProvider).upsert(entry);
    ref.invalidate(_weekProvider);
    if (sheetContext.mounted) Navigator.of(sheetContext).pop();
  }
}

final _weekProvider = StreamProvider.autoDispose.family(
    (ref, String weekStartDay) => ref
        .watch(planRepositoryProvider)
        .watchDays(weekDays(DateTime.parse(weekStartDay))));

class _DayRow extends ConsumerWidget {
  const _DayRow({
    required this.date,
    required this.day,
    required this.entries,
    required this.onAdd,
  });

  final DateTime date;
  final String day;
  final List<PlanEntry> entries;
  final VoidCallback onAdd;

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planned = entries.isNotEmpty;
    final isToday = day == DiaryEntry.dayOf(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onAdd,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                _Plate(planned: planned, highlight: isToday),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${_names[date.weekday - 1]} ${date.month}/${date.day}',
                          style: Theme.of(context).textTheme.titleMedium),
                      if (planned)
                        for (final e in entries)
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium),
                                    // The number the recipe already knows
                                    // (lens audit visual-display-10). Plain
                                    // text that wraps, never a Chip, and
                                    // absent when unknown, never a zero.
                                    if (e.kcalPerServing case final kcal?)
                                      Text('${kcal.round()} kcal per serving',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color:
                                                      AppColors.secondaryText(
                                                          context))),
                                  ],
                                ),
                              ),
                              // A deliberate tap: removes at once, with
                              // the app-wide Undo to hand it back.
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Remove ${e.title}',
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  final repo = ref.read(planRepositoryProvider);
                                  final undo = ref.read(undoControllerProvider);
                                  await repo.remove(e.id);
                                  undo.show(
                                    message: 'Removed ${e.title}',
                                    onUndo: () => repo.restore(e.id),
                                  );
                                },
                              ),
                            ],
                          )
                      else
                        Text('Tap to plan',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: AppColors.secondaryText(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The plate: an empty ring until the day is planned, butter-filled after.
class _Plate extends StatelessWidget {
  const _Plate({required this.planned, required this.highlight});

  final bool planned;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: planned ? AppColors.butter : Colors.transparent,
        border: Border.all(
          color: highlight ? AppColors.paprika : AppColors.stone,
          width: highlight ? 2.5 : 1.5,
        ),
      ),
      child: planned
          ? const Icon(Icons.restaurant, size: 18, color: AppColors.ink)
          : null,
    );
  }
}
