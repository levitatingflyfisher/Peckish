import 'package:peckish/features/diary/domain/diary_entry.dart';

/// Where a log for [targetDay] lands — the one rule, shared by every add
/// path (quick add, search, saved meals, barcode, AI guess).
///
/// Null or today's own key = today, resolved AT LOG TIME so a sheet left
/// open across midnight logs to the real now. A past day logs at that day's
/// noon, which sorts naturally among real entries and resolves back to the
/// same day key under [DiaryEntry.dayOf].
({String day, DateTime at}) dayStamp(String? targetDay, {DateTime? now}) {
  final at = now ?? DateTime.now();
  if (targetDay == null || targetDay == DiaryEntry.dayOf(at)) {
    return (day: DiaryEntry.dayOf(at), at: at);
  }
  return (day: targetDay, at: DateTime.parse('${targetDay}T12:00:00'));
}
