import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/diary/domain/day_stamp.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';

// The one rule for "which day does this land on", shared by every add path
// (quick add, search, saved meals, barcode, AI guess). It used to live
// private inside the + sheet, which is why the barcode path never had it.
void main() {
  test('no target day means today, stamped at the real now', () {
    final now = DateTime(2026, 8, 2, 19, 30);
    final stamp = dayStamp(null, now: now);

    expect(stamp.day, '2026-08-02');
    expect(stamp.at, now, reason: 'a now-flow keeps its real clock time');
  });

  test("today's own key is still the real now, not noon", () {
    final now = DateTime(2026, 8, 2, 19, 30);
    final stamp = dayStamp('2026-08-02', now: now);

    expect(stamp.at, now,
        reason: 'a sheet opened on today logs at the moment you tapped');
  });

  test('a past day lands at that day noon, and the two agree', () {
    final now = DateTime(2026, 8, 2, 0, 15);
    final stamp = dayStamp('2026-07-30', now: now);

    expect(stamp.day, '2026-07-30');
    expect(stamp.at, DateTime(2026, 7, 30, 12));
    // The pin that matters: the timestamp must resolve BACK to the same day
    // key, or a line would sort into one day and total into another.
    expect(DiaryEntry.dayOf(stamp.at), stamp.day);
  });

  test('a sheet left open across midnight logs to the new day', () {
    // Opened on the 1st with no target, tapped at 00:05 on the 2nd: the day
    // is resolved AT LOG TIME, never captured when the sheet was built.
    final stamp = dayStamp(null, now: DateTime(2026, 8, 2, 0, 5));

    expect(stamp.day, '2026-08-02');
  });
}
