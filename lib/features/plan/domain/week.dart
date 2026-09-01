import 'package:peckish/features/diary/domain/diary_entry.dart';

// The one rule for "a week" in the plan: Monday-first, built by calendar
// arithmetic (never by adding 24-hour Durations, which drift across a DST
// change). Plan's week stepper and the Groceries empty state's Set the table
// both use it, so the list is built from the same days from either door.

/// Local midnight of the Monday on or before [day].
DateTime mondayOf(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

/// The seven day stamps ('YYYY-MM-DD') of the week starting at [monday].
List<String> weekDays(DateTime monday) => [
      for (var i = 0; i < 7; i++)
        DiaryEntry.dayOf(DateTime(monday.year, monday.month, monday.day + i)),
    ];
