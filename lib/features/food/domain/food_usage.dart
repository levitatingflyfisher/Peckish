import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// A regular: one food the household actually reaches for, with how often
/// and how recently, plus the newest log's snapshot so a one-tap relog is
/// exact. Persistent — the diary is the ledger, this is the habit, and
/// deleting ledger lines never erases the habit.
class FoodUsage {
  const FoodUsage({
    required this.identityKey,
    required this.food,
    required this.label,
    required this.qty,
    required this.unitLabel,
    required this.grams,
    required this.macros,
    required this.useCount,
    required this.lastUsedAt,
    required this.hidden,
  });

  /// FoodRef.identityKey — 'u:<fdcId>' / 'c:<customId>' / 'q:<label>'.
  final String identityKey;
  final FoodRef food;
  final String label;
  final double qty;
  final String unitLabel;
  final double? grams;
  final MacroSet macros;
  final int useCount;
  final DateTime lastUsedAt;
  final bool hidden;

  /// The rail's relog template. Never inserted as-is — the rail copies it
  /// with a fresh id/day/at, exactly as it always did with entry templates.
  DiaryEntry asTemplateEntry() => DiaryEntry(
        id: 'regular:$identityKey',
        day: DiaryEntry.dayOf(lastUsedAt),
        at: lastUsedAt,
        food: food,
        label: label,
        qty: qty,
        unitLabel: unitLabel,
        grams: grams,
        macros: macros,
        source: EntrySource.tap,
        createdAt: lastUsedAt,
      );
}
