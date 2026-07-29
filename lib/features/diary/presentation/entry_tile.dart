import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// One diary line, wherever a day is shown (Today, a history day).
/// Swipe-away deletes; [onTap] is the edit hook.
class EntryTile extends ConsumerWidget {
  const EntryTile({super.key, required this.entry, this.onTap});

  final DiaryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.clay,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => ref.read(diaryRepositoryProvider).delete(entry.id),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: AppSpacing.sm,
        onTap: onTap,
        title: Text(entry.label),
        subtitle: Text(
          entry.qty == 1
              ? entry.unitLabel
              : '${entry.qty % 1 == 0 ? entry.qty.toInt() : entry.qty} × ${entry.unitLabel}',
        ),
        trailing: Text(
          entry.macros.kcal == null
              ? '—'
              : '${entry.macros.kcal!.round()} kcal',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.jam),
        ),
      ),
    );
  }
}
