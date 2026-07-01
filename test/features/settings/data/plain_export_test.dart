import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/diary_repository.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/settings/data/plain_export.dart';

// v0.1 shipped a bug here: the "Export data (plain JSON)" tile serialized a
// brand-new EMPTY PeckishExport — every plain export was a valid file with
// nothing in it. The plain export must gather through the same snapshot the
// encrypted backup uses.
void main() {
  test('the plain export carries what the diary actually holds', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await DiaryRepository(db).log(DiaryEntry(
      id: 'e-1',
      day: '2026-07-26',
      at: DateTime.utc(2026, 7, 26, 12),
      food: const FoodRef.quick(),
      label: 'Egg burrito',
      qty: 1,
      unitLabel: 'serving',
      grams: null,
      macros: const MacroSet(kcal: 249),
      source: EntrySource.manual,
      createdAt: DateTime.utc(2026, 7, 26, 12),
    ));

    final json = await buildPlainExport(db);
    expect(json, contains('Egg burrito'),
        reason: 'an export that silently drops the diary is worse than none');
    expect(json, contains('"app": "peckish"'));
  });
}
