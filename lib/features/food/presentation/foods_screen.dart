import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/extensions/qty_format.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';
import 'package:peckish/shared/widgets/num_field.dart';
import 'package:peckish/shared/widgets/input_modal.dart';

/// Foods — the full view behind the rail. Regulars (the persistent usage
/// record) are manageable here: log again, hide from the rail, bring back.
/// My Foods (household customs) get the CRUD the search sheet never had:
/// edit, archive, delete. Forgiveness over prevention — nothing here is a
/// dead end.
class FoodsScreen extends ConsumerWidget {
  const FoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regulars = ref.watch(_regularsProvider);
    final customs = ref.watch(_customsProvider);
    final text = Theme.of(context).textTheme;

    final live =
        (regulars.value ?? const <FoodUsage>[]).where((u) => !u.hidden);
    final hidden =
        (regulars.value ?? const <FoodUsage>[]).where((u) => u.hidden);
    final activeCustoms =
        (customs.value ?? const <CustomFood>[]).where((c) => !c.archived);
    final archivedCustoms =
        (customs.value ?? const <CustomFood>[]).where((c) => c.archived);

    final empty = regulars.hasValue &&
        customs.hasValue &&
        (regulars.value ?? const []).isEmpty &&
        (customs.value ?? const []).isEmpty;

    // One flat item list — headers included — so ListView.builder below only
    // instantiates the tiles that are actually on screen. A long-lived
    // household accumulates hundreds of regulars; building them all in one
    // frame is the kind of jank this screen never needs.
    final items = <Widget>[
      if (live.isNotEmpty || hidden.isNotEmpty) ...[
        Text('Regulars', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'What you actually reach for — deleting diary lines '
          'never clears this.',
          style: text.bodySmall?.copyWith(color: AppColors.stone),
        ),
        for (final u in live) _RegularTile(usage: u),
        if (hidden.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Hidden regulars', style: text.titleSmall),
            children: [
              for (final u in hidden) _RegularTile(usage: u, isHidden: true),
            ],
          ),
        const SizedBox(height: AppSpacing.lg),
      ],
      if (activeCustoms.isNotEmpty || archivedCustoms.isNotEmpty) ...[
        Text('My Foods', style: text.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Household-defined foods — per serving, yours to edit.',
          style: text.bodySmall?.copyWith(color: AppColors.stone),
        ),
        for (final c in activeCustoms) _CustomTile(food: c),
        if (archivedCustoms.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Resting', style: text.titleSmall),
            children: [
              for (final c in archivedCustoms)
                _CustomTile(food: c, isArchived: true),
            ],
          ),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Foods')),
      body: empty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  'Log a few foods and they gather here — your regulars '
                  'for one-tap relogging, and My Foods for the household '
                  'staples you define.',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: AppColors.stone),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: items.length,
              itemBuilder: (_, i) => items[i],
            ),
    );
  }
}

final _regularsProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(foodUsageRepositoryProvider).watchAll());
final _customsProvider = FutureProvider.autoDispose((ref) =>
    ref.watch(customFoodRepositoryProvider).getAll(includeArchived: true));

Future<void> _relog(WidgetRef ref, DiaryEntry template) async {
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
}

class _RegularTile extends ConsumerWidget {
  const _RegularTile({required this.usage, this.isHidden = false});

  final FoodUsage usage;
  final bool isHidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = usage.macros.kcal;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(usage.label),
      subtitle: Text('${usage.useCount}× · ${usage.unitLabel}'
          '${kcal == null ? '' : ' · ${kcal.round()} kcal'}'),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (choice) async {
          switch (choice) {
            case 'log':
              await _relog(ref, usage.asTemplateEntry());
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                      SnackBar(content: Text('Logged ${usage.label}')));
              }
            case 'hide':
              await ref
                  .read(foodUsageRepositoryProvider)
                  .setHidden(usage.identityKey, hidden: true);
            case 'show':
              await ref
                  .read(foodUsageRepositoryProvider)
                  .setHidden(usage.identityKey, hidden: false);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'log', child: Text('Log it again')),
          if (isHidden)
            const PopupMenuItem(value: 'show', child: Text('Show again'))
          else
            const PopupMenuItem(value: 'hide', child: Text('Hide from rail')),
        ],
      ),
    );
  }
}

class _CustomTile extends ConsumerWidget {
  const _CustomTile({required this.food, this.isArchived = false});

  final CustomFood food;
  final bool isArchived;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kcal = food.perServing.kcal;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.home_outlined, color: AppColors.paprika),
      title: Text(food.name),
      subtitle: Text(
          '${food.servingLabel}${kcal == null ? '' : ' · ${kcal.round()} kcal'}'),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (choice) async {
          final repo = ref.read(customFoodRepositoryProvider);
          switch (choice) {
            case 'log':
              await _relog(
                  ref,
                  DiaryEntry(
                    id: '',
                    day: '',
                    at: DateTime.now(),
                    food: FoodRef.custom(food.id),
                    label: food.name,
                    qty: 1,
                    unitLabel: food.servingLabel,
                    grams: null,
                    macros: food.perServing,
                    source: EntrySource.tap,
                    createdAt: DateTime.now(),
                  ));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                      SnackBar(content: Text('Logged ${food.name}')));
              }
            case 'edit':
              await showInputDialog<void>(
                context,
                builder: (_) => _EditFoodDialog(food: food),
              );
              ref.invalidate(_customsProvider);
            case 'rest':
              await repo.setArchived(food.id, archived: true);
              ref.invalidate(_customsProvider);
            case 'wake':
              await repo.setArchived(food.id, archived: false);
              ref.invalidate(_customsProvider);
            case 'delete':
              final sure = await showConfirmDialog(
                context,
                title: 'Delete ${food.name}?',
                message: 'Past diary entries keep their numbers — only the '
                    'food definition goes.',
              );
              if (sure) {
                await repo.delete(food.id);
                ref.invalidate(_customsProvider);
              }
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'log', child: Text('Log it again')),
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          if (isArchived)
            const PopupMenuItem(value: 'wake', child: Text('Back to My Foods'))
          else
            const PopupMenuItem(value: 'rest', child: Text('Rest this food')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

/// Edit a custom food in place. History is safe either way — diary entries
/// carry their own snapshots.
class _EditFoodDialog extends ConsumerStatefulWidget {
  const _EditFoodDialog({required this.food});

  final CustomFood food;

  @override
  ConsumerState<_EditFoodDialog> createState() => _EditFoodDialogState();
}

class _EditFoodDialogState extends ConsumerState<_EditFoodDialog> {
  late final TextEditingController _name;
  late final TextEditingController _serving;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;

  @override
  void initState() {
    super.initState();
    final f = widget.food;
    _name = TextEditingController(text: f.name);
    _serving = TextEditingController(text: f.servingLabel);
    _kcal = TextEditingController(text: _fmt(f.perServing.kcal));
    _protein = TextEditingController(text: _fmt(f.perServing.proteinG));
    _carbs = TextEditingController(text: _fmt(f.perServing.carbG));
    _fat = TextEditingController(text: _fmt(f.perServing.fatG));
  }

  @override
  void dispose() {
    for (final c in [_name, _serving, _kcal, _protein, _carbs, _fat]) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double? v) => v == null ? '' : formatQty(v);

  static double? _num(TextEditingController c) => parseFlexibleDouble(c.text);

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await ref.read(customFoodRepositoryProvider).update(widget.food.copyWith(
          name: name,
          servingLabel: _serving.text.trim().isEmpty
              ? widget.food.servingLabel
              : _serving.text.trim(),
          perServing: MacroSet(
            kcal: _num(_kcal),
            proteinG: _num(_protein),
            carbG: _num(_carbs),
            fatG: _num(_fat),
          ),
        ));
    if (mounted) Navigator.of(context).pop();
  }

  Widget _numField(TextEditingController c, String label) =>
      NumField(controller: c, label: label);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit food'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
                controller: _serving,
                decoration:
                    const InputDecoration(labelText: 'Serving (e.g. 1 bowl)')),
            _numField(_kcal, 'kcal'),
            _numField(_protein, 'Protein g'),
            _numField(_carbs, 'Carbs g'),
            _numField(_fat, 'Fat g'),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
