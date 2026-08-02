import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';

// The two hot lookups grow with the install's age: the diary is filtered by
// day on every Today/History build, and portions are filtered by fdc_id on
// every USDA food pick. Without indexes both are full scans that get slower
// every month of use — the opposite of how a potato phone should age.
void main() {
  test('the day and portion lookups are indexed', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // beforeOpen runs on first real query.
    await db.customSelect('SELECT 1').get();

    final indexes = (await db
            .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'index'")
            .get())
        .map((row) => row.read<String>('name'))
        .toSet();

    expect(indexes, contains('idx_diary_entries_day'));
    expect(indexes, contains('idx_usda_portions_fdc_id'));
  });
}
