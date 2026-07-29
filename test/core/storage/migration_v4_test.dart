import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

// v3 → v4 adds the four per-macro ROLE columns to targets ('about' /
// 'atLeast' / 'under'; null = the axis default). Existing numbers must
// survive untouched — a target you set in v0.3 keeps meaning what it meant.
// Non-transactional caution as ever: each ALTER is guarded, so a re-entered
// migration that already added some columns adds only the missing rest.
void main() {
  // targets exactly as drift created it at v1..v3.
  const targetsDdl =
      'CREATE TABLE "targets" ("id" INTEGER NOT NULL DEFAULT 1, '
      '"kcal" REAL, "protein_g" REAL, "carb_g" REAL, "fat_g" REAL, '
      'PRIMARY KEY ("id"))';

  sqlite3.Database seedV3() {
    final raw = sqlite3.sqlite3.openInMemory();
    raw.execute(targetsDdl);
    raw.execute(
        'INSERT INTO targets (id, kcal, protein_g) VALUES (1, 2000, 150)');
    raw.execute('PRAGMA user_version = 3');
    return raw;
  }

  Future<Set<String>> columnsOf(AppDatabase db) async {
    final info = await db.customSelect('PRAGMA table_info(targets)').get();
    return {for (final row in info) row.read<String>('name')};
  }

  test('v3 → v4 adds the role columns and keeps the numbers', () async {
    final db = AppDatabase(NativeDatabase.opened(seedV3()));
    addTearDown(db.close);

    expect(
        await columnsOf(db),
        containsAll(
            ['kcal_role', 'protein_role', 'carb_role', 'fat_role']));

    final row = await db
        .customSelect('SELECT kcal, protein_g, kcal_role FROM targets')
        .getSingle();
    expect(row.read<double>('kcal'), 2000);
    expect(row.read<double>('protein_g'), 150);
    expect(row.readNullable<String>('kcal_role'), isNull,
        reason: 'pre-roles rows carry no explicit role');
  });

  test('re-entry adds only the missing columns, without crashing', () async {
    final raw = seedV3();
    // Half-run: one role column landed, then the migration died before the
    // version stamp. The re-run must fill in the other three.
    raw.execute('ALTER TABLE targets ADD COLUMN kcal_role TEXT');

    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    expect(
        await columnsOf(db),
        containsAll(
            ['kcal_role', 'protein_role', 'carb_role', 'fat_role']));
  });

  test('a fresh database has the role columns from birth', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(
        await columnsOf(db),
        containsAll(
            ['kcal_role', 'protein_role', 'carb_role', 'fat_role']));
  });
}
