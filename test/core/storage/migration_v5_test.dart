import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

// v4 → v5 adds `barcode` to custom_foods: the code a saved food came off,
// so scanning the tin again answers off your own shelf. Nothing to backfill
// — foods saved before this release never recorded one, and they keep
// working exactly as they did.
//
// Non-transactional caution as ever (the StillLife lesson): the ALTER is
// guarded, so a re-entered migration is a no-op rather than a crash.
void main() {
  // custom_foods exactly as drift created it at v2..v4.
  const customFoodsDdl =
      'CREATE TABLE "custom_foods" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
      '"serving_label" TEXT NOT NULL, "kcal" REAL, "protein_g" REAL, '
      '"carb_g" REAL, "fat_g" REAL, "created_at" INTEGER NOT NULL, '
      '"archived" INTEGER NOT NULL DEFAULT 0, "hlc" TEXT, "node_id" TEXT, '
      '"is_deleted" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"))';

  sqlite3.Database seedV4() {
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute(customFoodsDdl);
    raw.execute('INSERT INTO custom_foods '
        '(id, name, serving_label, kcal, created_at, archived, is_deleted) '
        "VALUES ('cafe-rio', 'Cafe Rio salad', '1 salad', 800, 0, 0, 0)");
    raw.execute('PRAGMA user_version = 4');
    return raw;
  }

  Future<Set<String>> columnsOf(AppDatabase db) async {
    final info =
        await db.customSelect('PRAGMA table_info(custom_foods)').get();
    return {for (final row in info) row.read<String>('name')};
  }

  test('v4 → v5 adds barcode and leaves every saved food intact', () async {
    final db = AppDatabase(NativeDatabase.opened(seedV4()));
    addTearDown(db.close);

    expect(await columnsOf(db), contains('barcode'));

    final row = await db
        .customSelect('SELECT name, kcal, barcode FROM custom_foods')
        .getSingle();
    expect(row.read<String>('name'), 'Cafe Rio salad');
    expect(row.read<double>('kcal'), 800);
    expect(row.readNullable<String>('barcode'), isNull,
        reason: 'a food that never came off a package has no code');
  });

  test('re-entry after the column already landed is a no-op', () async {
    final raw = seedV4();
    // Half-run: the ALTER landed, then the migration died before the
    // version stamp.
    raw.execute('ALTER TABLE custom_foods ADD COLUMN barcode TEXT');

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    expect(await columnsOf(db), contains('barcode'));
  });

  test('a partial schema is skipped, not crashed through', () async {
    // Migration fixtures (and a database damaged in the field) open with
    // only some tables present. A column-adder that assumes its table
    // exists turns that into an app that cannot open at all.
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute('CREATE TABLE "targets" ("id" INTEGER NOT NULL DEFAULT 1, '
        '"kcal" REAL, PRIMARY KEY ("id"))');
    raw.execute('PRAGMA user_version = 4');

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    await expectLater(
        db.customSelect('SELECT kcal FROM targets').get(), completes);
  });

  test('a fresh database has barcode from birth', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(await columnsOf(db), contains('barcode'));
  });
}
