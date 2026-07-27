import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

// The app's FIRST real migration: v1 → v2 adds the sync columns
// (hlc, node_id, is_deleted) to the five household-shared tables. Purely
// additive ALTERs, but drift migrations are not transactional (the
// StillLife lesson), so each ALTER is guarded by a column-existence check —
// this test proves both the upgrade and its re-entry safety.
void main() {
  // The five synced tables exactly as drift created them at schema v1
  // (hand-transcribed from app_database.dart's v1 shape).
  const v1Ddl = [
    'CREATE TABLE "custom_foods" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
        '"serving_label" TEXT NOT NULL, "kcal" REAL, "protein_g" REAL, '
        '"carb_g" REAL, "fat_g" REAL, "created_at" INTEGER NOT NULL, '
        '"archived" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"))',
    'CREATE TABLE "saved_meals" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
        '"position" INTEGER NOT NULL, "created_at" INTEGER NOT NULL, '
        '"last_used_at" INTEGER, "archived" INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY ("id"))',
    'CREATE TABLE "recipes" ("id" TEXT NOT NULL, "title" TEXT NOT NULL, '
        '"servings" REAL, "source_url" TEXT, '
        '"instructions" TEXT NOT NULL DEFAULT \'\', "declared_kcal" REAL, '
        '"declared_protein_g" REAL, "declared_carb_g" REAL, '
        '"declared_fat_g" REAL, "created_at" INTEGER NOT NULL, '
        '"archived" INTEGER NOT NULL DEFAULT 0, PRIMARY KEY ("id"))',
    'CREATE TABLE "plan_entries" ("id" TEXT NOT NULL, "day" TEXT NOT NULL, '
        '"slot" INTEGER NOT NULL, "kind" INTEGER NOT NULL, "ref_id" TEXT, '
        '"note" TEXT, PRIMARY KEY ("id"))',
    'CREATE TABLE "grocery_items" ("id" TEXT NOT NULL, "name" TEXT NOT NULL, '
        '"aisle" INTEGER NOT NULL, "checked" INTEGER NOT NULL DEFAULT 0, '
        '"manual" INTEGER NOT NULL DEFAULT 0, "source_recipe_id" TEXT, '
        '"created_at" INTEGER NOT NULL, PRIMARY KEY ("id"))',
  ];

  sqlite3.Database seedV1() {
    final raw = sqlite3.sqlite3.openInMemory();
    for (final ddl in v1Ddl) {
      raw.execute(ddl);
    }
    raw.execute("INSERT INTO custom_foods (id, name, serving_label, kcal, "
        "created_at) VALUES ('cf-1', 'Cafe Rio salad', '1 salad', 640, 0)");
    raw.execute("INSERT INTO grocery_items (id, name, aisle, created_at) "
        "VALUES ('g-1', 'Milk', 2, 0)");
    raw.execute('PRAGMA user_version = 1');
    return raw;
  }

  test('v1 → v2 adds the sync columns and preserves every row', () async {
    final raw = seedV1();
    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Opening runs the migration; the v1 rows must survive with sane
    // defaults in the new columns.
    final foods = await db.select(db.customFoods).get();
    expect(foods.single.name, 'Cafe Rio salad');
    expect(foods.single.kcal, 640);
    expect(foods.single.isDeleted, isFalse);
    expect(foods.single.hlc, isNull);
    expect(foods.single.nodeId, isNull);

    final items = await db.select(db.groceryItems).get();
    expect(items.single.name, 'Milk');
    expect(items.single.isDeleted, isFalse);
  });

  test('the migration is re-entry safe (StillLife lesson: not transactional)',
      () async {
    final raw = seedV1();
    // Simulate a half-run migration: one table already has its columns.
    raw.execute('ALTER TABLE custom_foods ADD COLUMN hlc TEXT');
    raw.execute('ALTER TABLE custom_foods ADD COLUMN node_id TEXT');
    raw.execute('ALTER TABLE custom_foods ADD COLUMN is_deleted INTEGER '
        'NOT NULL DEFAULT 0');

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // A blind re-run would throw "duplicate column name"; the guarded one
    // completes and every table ends up whole.
    final foods = await db.select(db.customFoods).get();
    expect(foods.single.isDeleted, isFalse);
    final items = await db.select(db.groceryItems).get();
    expect(items.single.isDeleted, isFalse);
  });

  test('a fresh v2 database has the columns from birth', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.customFoods).insert(CustomFoodsCompanion.insert(
          id: 'cf-2',
          name: 'Rolls',
          servingLabel: '2 rolls',
          createdAt: DateTime(2026),
        ));
    final row = await db.select(db.customFoods).getSingle();
    expect(row.isDeleted, isFalse);
    expect(row.hlc, isNull);
  });
}
