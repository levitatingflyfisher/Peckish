import 'package:uuid/uuid.dart';

import 'package:peckish/features/diary/domain/day_stamp.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';

/// "Log this again" — one fresh line copied from a food you have logged
/// before, on whatever day you are feeding.
///
/// Every one-tap path goes through here: the regulars rail, the + sheet's
/// regulars, a past day's rail, the round-out card's ideas, and a barcode
/// that lands on a food you already saved. Living beside [dayStamp] for the
/// same reason: the day rule was private to the + sheet once, which is
/// exactly why the barcode path could only ever write "now".
///
/// [day] null means today, resolved at log time. [count] scales a template
/// up — two eggs, not one — and everything that should scale scales with
/// it. The unit is what ONE of them is called, so it never multiplies.
DiaryEntry relogEntry(
  DiaryEntry template, {
  String? day,
  int count = 1,
  DateTime? now,
  String? id,
}) {
  final realNow = now ?? DateTime.now();
  final stamp = dayStamp(day, now: realNow);
  return DiaryEntry(
    id: id ?? const Uuid().v4(),
    day: stamp.day,
    at: stamp.at,
    food: template.food,
    label: template.label,
    qty: template.qty * count,
    unitLabel: template.unitLabel,
    grams: template.grams == null ? null : template.grams! * count,
    macros: template.macros * count.toDouble(),
    source: EntrySource.tap,
    // `at` moves to the day being fed; this stays the real now — the ledger
    // can always say when you actually wrote a thing down.
    createdAt: realNow,
  );
}
