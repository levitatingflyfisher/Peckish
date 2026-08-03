import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/extensions/qty_format.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/num_field.dart';
import 'package:peckish/shared/widgets/input_modal.dart';

/// Fix a logged line in place — the "logged one, actually ate two" errand.
/// Changing the qty rescales the numbers from the line's own per-unit
/// shape; typing a number directly always wins (the rescale only ever
/// runs when the qty field itself changes). Saving goes through
/// [DiaryRepository.update], so the regulars snapshot heals too.
Future<void> showEditEntrySheet(BuildContext context, DiaryEntry entry) =>
    showInputDialog<void>(
      context,
      builder: (_) => _EditEntryDialog(entry: entry),
    );

class _EditEntryDialog extends ConsumerStatefulWidget {
  const _EditEntryDialog({required this.entry});

  final DiaryEntry entry;

  @override
  ConsumerState<_EditEntryDialog> createState() => _EditEntryDialogState();
}

class _EditEntryDialogState extends ConsumerState<_EditEntryDialog> {
  late final TextEditingController _label;
  late final TextEditingController _qty;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  bool _saving = false;

  /// Guards the qty→macros rescale so it never loops through its own
  /// programmatic writes.
  bool _rescaling = false;

  static String _show(double? v) => v == null ? '' : formatQty(v);

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _label = TextEditingController(text: e.label);
    _qty = TextEditingController(text: _show(e.qty));
    _kcal = TextEditingController(text: _show(e.macros.kcal));
    _protein = TextEditingController(text: _show(e.macros.proteinG));
    _carbs = TextEditingController(text: _show(e.macros.carbG));
    _fat = TextEditingController(text: _show(e.macros.fatG));
    _qty.addListener(_rescale);
  }

  /// Refill the macro fields from the ORIGINAL per-unit shape × new qty.
  /// Runs only on qty edits — direct macro edits are never overwritten
  /// behind the user's back.
  void _rescale() {
    if (_rescaling) return;
    final newQty = parseFlexibleDouble(_qty.text);
    final origQty = widget.entry.qty;
    if (newQty == null || newQty <= 0 || origQty <= 0) return;
    final scaled = widget.entry.macros * (newQty / origQty);
    _rescaling = true;
    _kcal.text = _show(scaled.kcal);
    _protein.text = _show(scaled.proteinG);
    _carbs.text = _show(scaled.carbG);
    _fat.text = _show(scaled.fatG);
    _rescaling = false;
  }

  @override
  void dispose() {
    _label.dispose();
    _qty.dispose();
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  static double? _num(TextEditingController c) => parseFlexibleDouble(c.text);

  Future<void> _save() async {
    if (_saving) return;
    _saving = true;
    final e = widget.entry;
    final qty = _num(_qty) ?? e.qty;
    await ref.read(diaryRepositoryProvider).update(DiaryEntry(
          id: e.id,
          day: e.day,
          at: e.at,
          food: e.food,
          label: _label.text.trim().isEmpty ? e.label : _label.text.trim(),
          qty: qty,
          unitLabel: e.unitLabel,
          grams: e.grams == null || e.qty <= 0
              ? e.grams
              : e.grams! * (qty / e.qty),
          macros: MacroSet(
            kcal: _num(_kcal),
            proteinG: _num(_protein),
            carbG: _num(_carbs),
            fatG: _num(_fat),
          ),
          source: e.source,
          createdAt: e.createdAt,
        ));
    if (mounted) Navigator.of(context).pop();
  }

  Widget _numField(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: NumField(controller: c, label: label, outlined: true),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Fix this line'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: TextField(
                controller: _label,
                decoration: const InputDecoration(
                    labelText: 'What was it?', border: OutlineInputBorder()),
              ),
            ),
            _numField(_qty, 'Qty'),
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
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
