import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

// v2 → v3 creates the food_usages table (persistent regulars) and backfills
// it from the existing diary — so the rail survives the update with the
// user's habits intact, not empty. Same non-transactional caution as v2:
// the create + backfill only run when the table is genuinely absent, so a
// re-entered migration cannot double-count.
void main() {
  // diary_entries exactly as drift created it at v2 (dateTime = unix seconds).
  const diaryDdl =
      'CREATE TABLE "diary_entries" ("id" TEXT NOT NULL, "day" TEXT NOT NULL, '
      '"at" INTEGER NOT NULL, "food_kind" INTEGER NOT NULL, '
      '"usda_fdc_id" INTEGER, "custom_food_id" TEXT, "label" TEXT NOT NULL, '
      '"qty" REAL NOT NULL, "unit_label" TEXT NOT NULL, "grams" REAL, '
      '"kcal" REAL, "protein_g" REAL, "carb_g" REAL, "fat_g" REAL, '
      '"source" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, '
      'PRIMARY KEY ("id"))';

  sqlite3.Database seedV2() {
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute(diaryDdl);
    // Two logs of the same quick food (newest carries kcal 160), one custom.
    raw.execute("INSERT INTO diary_entries (id, day, at, food_kind, label, "
        "qty, unit_label, kcal, source, created_at) VALUES "
        "('e-1', '2026-07-01', 100, 2, 'Oats', 1, 'serving', 150, 2, 100)");
    raw.execute("INSERT INTO diary_entries (id, day, at, food_kind, label, "
        "qty, unit_label, kcal, source, created_at) VALUES "
        "('e-2', '2026-07-02', 200, 2, 'Oats', 1, 'serving', 160, 2, 200)");
    raw.execute("INSERT INTO diary_entries (id, day, at, food_kind, "
        "custom_food_id, label, qty, unit_label, kcal, source, created_at) "
        "VALUES ('e-3', '2026-07-02', 300, 1, 'cf-1', 'Salad', 1, 'salad', "
        "640, 1, 300)");
    raw.execute('PRAGMA user_version = 2');
    return raw;
  }

  test('v2 → v3 backfills the regulars from the existing diary', () async {
    final db = AppDatabase(NativeDatabase.opened(seedV2()));
    addTearDown(db.close);

    final rows = await (db.select(db.foodUsages)).get();
    expect(rows, hasLength(2));

    final oats = rows.singleWhere((r) => r.label == 'Oats');
    expect(oats.useCount, 2);
    expect(oats.at.millisecondsSinceEpoch, 200 * 1000);
    expect(oats.kcal, 160, reason: 'the newest snapshot wins');
    expect(oats.hidden, isFalse);

    final salad = rows.singleWhere((r) => r.label == 'Salad');
    expect(salad.useCount, 1);
    expect(salad.customFoodId, 'cf-1');
  });

  test('re-entry cannot double-count (table already present)', () async {
    final raw = seedV2();
    // Simulate a half-run: the table exists and was backfilled once, but the
    // version stamp never landed. A blind re-run would re-add the rows.
    raw.execute('CREATE TABLE "food_usages" ("identity_key" TEXT NOT NULL, '
        '"food_kind" INTEGER NOT NULL, "usda_fdc_id" INTEGER, '
        '"custom_food_id" TEXT, "label" TEXT NOT NULL, "qty" REAL NOT NULL, '
        '"unit_label" TEXT NOT NULL, "grams" REAL, "kcal" REAL, '
        '"protein_g" REAL, "carb_g" REAL, "fat_g" REAL, '
        '"use_count" INTEGER NOT NULL, "at" INTEGER NOT NULL, '
        '"hidden" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("identity_key"))');
    raw.execute("INSERT INTO food_usages (identity_key, food_kind, label, "
        "qty, unit_label, kcal, use_count, at) VALUES "
        "('q:oats', 2, 'Oats', 1, 'serving', 160, 2, 200)");

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final rows = await (db.select(db.foodUsages)).get();
    expect(rows, hasLength(1), reason: 'no re-backfill on re-entry');
    expect(rows.single.useCount, 2);
  });

  test('a fresh v3 database has the table from birth', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await db.select(db.foodUsages).get(), isEmpty);
  });
}
