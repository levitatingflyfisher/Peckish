import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:uuid/uuid.dart';

/// Confirm-before-commit for a scanned product: nothing touches the ledger
/// until the user confirms the grams. What lands is a snapshot scaled to
/// that amount, provenance `scan`. Resolves true when a line was logged,
/// null/false on dismiss — the scan screen pops itself on a log.
Future<bool?> showProductSheet(BuildContext context, OffProduct product) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductSheet(product: product),
    );

class _ProductSheet extends ConsumerStatefulWidget {
  const _ProductSheet({required this.product});

  final OffProduct product;

  @override
  ConsumerState<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends ConsumerState<_ProductSheet> {
  late final TextEditingController _grams;
  bool _saveToMyFoods = false;

  double get _defaultGrams => widget.product.servingGrams ?? 100;

  @override
  void initState() {
    super.initState();
    _grams = TextEditingController(text: _fmt(_defaultGrams));
  }

  @override
  void dispose() {
    _grams.dispose();
    super.dispose();
  }

  double get _currentGrams =>
      double.tryParse(_grams.text.replaceAll(',', '.')) ?? _defaultGrams;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final scaled = product.per100g.forGrams(_currentGrams).clamped();
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(product.displayName, style: theme.textTheme.titleLarge),
          if (product.servingLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('Label serving: ${product.servingLabel}',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _grams,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              suffixText: 'g',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '≈ ${_slot(scaled.kcal, 'kcal', round: true)} · '
            'protein ${_slot(scaled.proteinG, 'g')} · '
            'carbs ${_slot(scaled.carbG, 'g')} · '
            'fat ${_slot(scaled.fatG, 'g')}',
            style: theme.textTheme.bodyMedium,
          ),
          CheckboxListTile(
            value: _saveToMyFoods,
            onChanged: (v) => setState(() => _saveToMyFoods = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Save to My Foods'),
            subtitle: const Text('So next time is one tap'),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _log(context),
              child: const Text('Log it'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _log(BuildContext context) async {
    final product = widget.product;
    final grams = _currentGrams;
    final macros = product.per100g.forGrams(grams).clamped();

    var food = const FoodRef.quick();
    if (_saveToMyFoods) {
      final servingGrams = product.servingGrams ?? 100;
      final id = const Uuid().v4();
      await ref.read(customFoodRepositoryProvider).create(CustomFood(
            id: id,
            name: product.displayName,
            servingLabel: product.servingLabel ?? '100 g',
            perServing: product.per100g.forGrams(servingGrams).clamped(),
            createdAt: DateTime.now(),
          ));
      food = FoodRef.custom(id);
    }

    final now = DateTime.now();
    await ref.read(diaryRepositoryProvider).log(DiaryEntry(
          id: const Uuid().v4(),
          day: DiaryEntry.dayOf(now),
          at: now,
          food: food,
          label: product.displayName,
          qty: grams,
          unitLabel: 'g',
          grams: grams,
          macros: macros,
          source: EntrySource.scan,
          createdAt: now,
        ));

    if (context.mounted) Navigator.of(context).pop(true);
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// '81 kcal' / '6.3 g' / '—' when the label didn't say.
  static String _slot(double? v, String unit, {bool round = false}) {
    if (v == null) return '—';
    final shown = round ? v.round().toString() : _fmt((v * 10).round() / 10);
    return '$shown $unit';
  }
}
