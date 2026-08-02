import 'package:flutter/material.dart';

import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// A day's four numbers against the targets you set: the big kcal figure
/// and a chip per macro. Plain arithmetic, never a verdict — a heavy day is
/// information.
///
/// Shared by Today and by any past day you open, because "what did I
/// actually eat on the 19th" is a question you ask about the past far more
/// often than about now, and a dot on a trend line is a shape, not a
/// number. An unknown macro reads '—': a day logged in kcal alone did not
/// eat zero protein.
class TotalsCard extends StatelessWidget {
  const TotalsCard({super.key, required this.totals, required this.targets});

  final MacroSet totals;
  final DailyTargets targets;

  static String _fmt(double? v) => v == null ? '0' : v.round().toString();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final kcalTarget = targets.values.kcal;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    _fmt(totals.kcal),
                    style: text.displayMedium?.copyWith(
                      color: AppColors.paprika,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    kcalTarget == null
                        ? 'kcal'
                        : 'of ${targets.resolvedKcalRole.mark}'
                            '${_fmt(kcalTarget)} kcal',
                    style: text.titleMedium?.copyWith(color: AppColors.stone),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _MacroChip(
                    label: 'Protein',
                    value: totals.proteinG,
                    target: targets.values.proteinG,
                    role: targets.resolvedProteinRole,
                    color: AppColors.sage),
                _MacroChip(
                    label: 'Carbs',
                    value: totals.carbG,
                    target: targets.values.carbG,
                    role: targets.resolvedCarbRole,
                    color: AppColors.butter),
                _MacroChip(
                    label: 'Fat',
                    value: totals.fatG,
                    target: targets.values.fatG,
                    role: targets.resolvedFatRole,
                    color: AppColors.clay),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroChip extends StatelessWidget {
  const _MacroChip({
    required this.label,
    required this.value,
    required this.target,
    required this.role,
    required this.color,
  });

  final String label;
  final double? value;
  final double? target;
  final TargetRole role;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final v = value == null ? '—' : '${value!.round()}g';
    final suffix = target == null ? '' : ' / ${role.mark}${target!.round()}g';
    return Chip(
      avatar: CircleAvatar(backgroundColor: color, radius: 6),
      label: Text('$label $v$suffix'),
      visualDensity: VisualDensity.comfortable,
    );
  }
}
