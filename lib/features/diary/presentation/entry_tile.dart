import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/presentation/edit_entry_sheet.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/shared/extensions/qty_format.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';

/// One diary line, wherever a day is shown (Today, a history day). A tap
/// opens the fix-this-line sheet unless the caller overrides [onTap].
///
/// Swipe-away asks first (the user explicitly asked for a delete
/// confirmation) and, once removed, offers Undo — VISION.md's "forgiveness
/// over prevention applies to data too" law used to be broken here: an
/// unconfirmed swipe was a silent hard-delete with no way back.
class EntryTile extends ConsumerWidget {
  const EntryTile({super.key, required this.entry, this.onTap});

  final DiaryEntry entry;
  final VoidCallback? onTap;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    // Read the repository itself, not `ref` — by the time Undo is tapped
    // this tile is long gone from the tree (that IS the delete), and a
    // ConsumerWidget's `ref` throws once its element is disposed.
    final repo = ref.read(diaryRepositoryProvider);
    await repo.delete(entry.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('Removed ${entry.label}'),
        action: SnackBarAction(
          label: 'Undo',
          // Re-insert the captured row verbatim — same id/day/at/macros —
          // never touching the usage table (undoing a delete is not a
          // fresh use of the food).
          onPressed: () => repo.restore(entry),
        ),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showConfirmDialog(
        context,
        title: 'Delete ${entry.label}?',
        message: 'This line comes off the ledger — Undo puts it straight '
            'back if you change your mind.',
      ),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.clay,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _delete(context, ref),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: AppSpacing.sm,
        onTap: onTap ?? () => showEditEntrySheet(context, entry),
        title: Text(entry.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              entry.qty == 1
                  ? entry.unitLabel
                  : '${formatQty(entry.qty)} × ${entry.unitLabel}',
            ),
            // Day totals already show all four macros; a day-list line
            // showed kcal alone even though every entry snapshots P/C/F
            // too. Plain text, never a Chip — a Chip clips its own label
            // instead of wrapping, the exact shear totals_card.dart's
            // pills learned to avoid. Omitted entirely when every slot is
            // unknown: a bare kcal entry has nothing extra to say.
            if (_macroLine(entry.macros) case final line?)
              Text(
                line,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppColors.stone),
              ),
          ],
        ),
        trailing: Text(
          entry.macros.kcal == null
              ? '—'
              : '${entry.macros.kcal!.round()} kcal',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: AppColors.paprika),
        ),
      ),
    );
  }

  /// 'P 32 · C 45 · F 12' — g, rounded the way every other number on this
  /// entry is (formatQty). A missing slot reads '—', never a fake 0; null
  /// when every slot is unknown, so the caller can omit the line entirely.
  static String? _macroLine(MacroSet m) {
    if (m.proteinG == null && m.carbG == null && m.fatG == null) return null;
    String slot(double? v) => v == null ? '—' : formatQty(v);
    return 'P ${slot(m.proteinG)} · C ${slot(m.carbG)} · F ${slot(m.fatG)}';
  }
}
