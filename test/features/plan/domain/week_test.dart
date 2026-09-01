import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/plan/domain/week.dart';

// One rule for "this week", shared by Plan and the Groceries empty state,
// so Set the table builds the same days from either door.
void main() {
  test('the week starts on the Monday on or before the day', () {
    expect(mondayOf(DateTime(2026, 9, 27, 18)), DateTime(2026, 9, 21));
    expect(mondayOf(DateTime(2026, 9, 21, 7)), DateTime(2026, 9, 21));
  });

  test('a week is seven day stamps from its Monday', () {
    expect(weekDays(DateTime(2026, 9, 28)), [
      '2026-09-28',
      '2026-09-29',
      '2026-09-30',
      '2026-10-01',
      '2026-10-02',
      '2026-10-03',
      '2026-10-04',
    ]);
  });
}
