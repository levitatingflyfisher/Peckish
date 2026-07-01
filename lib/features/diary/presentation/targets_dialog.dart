import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// The daily-targets editor. The minimal path is two typed numbers —
/// calories and protein — because the role defaults already say what most
/// people mean (protein is a floor, the rest is "about"). Every box is
/// optional; an empty box is simply not part of your day.
Future<void> showTargetsDialog(BuildContext context, WidgetRef ref) async {
  final current = await ref.read(targetsRepositoryProvider).get();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _TargetsDialog(initial: current),
  );
}

class _TargetsDialog extends ConsumerStatefulWidget {
  const _TargetsDialog({required this.initial});

  final DailyTargets initial;

  @override
  ConsumerState<_TargetsDialog> createState() => _TargetsDialogState();
}

class _TargetsDialogState extends ConsumerState<_TargetsDialog> {
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  late TargetRole _kcalRole;
  late TargetRole _proteinRole;
  late TargetRole _carbRole;
  late TargetRole _fatRole;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.initial;
    String show(double? v) =>
        v == null ? '' : (v % 1 == 0 ? v.toInt().toString() : v.toString());
    _kcal = TextEditingController(text: show(t.values.kcal));
    _protein = TextEditingController(text: show(t.values.proteinG));
    _carbs = TextEditingController(text: show(t.values.carbG));
    _fat = TextEditingController(text: show(t.values.fatG));
    _kcalRole = t.resolvedKcalRole;
    _proteinRole = t.resolvedProteinRole;
    _carbRole = t.resolvedCarbRole;
    _fatRole = t.resolvedFatRole;
  }

  @override
  void dispose() {
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  static double? _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.'));

  Widget _row(TextEditingController c, String label, TargetRole role,
          ValueChanged<TargetRole> onRole) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: c,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: label, border: const OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            DropdownButton<TargetRole>(
              value: role,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                    value: TargetRole.about, child: Text('About')),
                DropdownMenuItem(
                    value: TargetRole.atLeast, child: Text('At least')),
                DropdownMenuItem(
                    value: TargetRole.under, child: Text('Under')),
              ],
              onChanged: (r) => r == null ? null : onRole(r),
            ),
          ],
        ),
      );

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final values = MacroSet(
      kcal: _num(_kcal),
      proteinG: _num(_protein),
      carbG: _num(_carbs),
      fatG: _num(_fat),
    );
    // Roles are stored exactly as shown, but only for axes that have a
    // number — an empty box has no meaning to qualify.
    await ref.read(targetsRepositoryProvider).set(DailyTargets(
          values: values,
          kcalRole: values.kcal == null ? null : _kcalRole,
          proteinRole: values.proteinG == null ? null : _proteinRole,
          carbRole: values.carbG == null ? null : _carbRole,
          fatRole: values.fatG == null ? null : _fatRole,
        ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Daily targets'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'All optional — leave a box empty to skip it. "At least" is '
              'a floor to reach; "Under" is a budget to stay within.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            _row(_kcal, 'Calories', _kcalRole,
                (r) => setState(() => _kcalRole = r)),
            _row(_protein, 'Protein g', _proteinRole,
                (r) => setState(() => _proteinRole = r)),
            _row(_carbs, 'Carbs g', _carbRole,
                (r) => setState(() => _carbRole = r)),
            _row(_fat, 'Fat g', _fatRole,
                (r) => setState(() => _fatRole = r)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
