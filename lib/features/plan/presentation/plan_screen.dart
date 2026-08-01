import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/input_modal.dart';

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
    final now = DateTime.now();
    _weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
  }

  List<String> get _days => [
        for (var i = 0; i < 7; i++)
          DiaryEntry.dayOf(_weekStart.add(Duration(days: i))),
      ];

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
      appBar: AppBar(
        title: Text(_weekTitle()),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous week',
          onPressed: () => setState(
              () => _weekStart = _weekStart.subtract(const Duration(days: 7))),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next week',
            onPressed: () => setState(
                () => _weekStart = _weekStart.add(const Duration(days: 7))),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          for (var i = 0; i < 7; i++)
            _DayRow(
              date: _weekStart.add(Duration(days: i)),
              day: _days[i],
              entries: byDay[_days[i]] ?? const [],
              onAdd: () => _showAddToDay(context, _days[i]),
            ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            icon: const Icon(Icons.shopping_basket_outlined),
            label: const Text('Set the table — build the grocery list'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: () async {
              await ref
                  .read(groceryRepositoryProvider)
                  .regenerateFromPlan(_days);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Grocery list refilled from this week’s plan')));
              }
            },
          ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  String _weekTitle() {
    final end = _weekStart.add(const Duration(days: 6));
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

final _weekProvider =
    StreamProvider.autoDispose.family((ref, String weekStartDay) {
  final start = DateTime.parse(weekStartDay);
  final days = [
    for (var i = 0; i < 7; i++) DiaryEntry.dayOf(start.add(Duration(days: i))),
  ];
  return ref.watch(planRepositoryProvider).watchDays(days);
});

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
                                child: Text(e.title,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        Theme.of(context).textTheme.bodyMedium),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                tooltip: 'Remove',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => ref
                                    .read(planRepositoryProvider)
                                    .remove(e.id),
                              ),
                            ],
                          )
                      else
                        Text('Tap to plan',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppColors.stone)),
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
