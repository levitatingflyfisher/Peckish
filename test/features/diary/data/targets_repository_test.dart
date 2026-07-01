import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

// Daily targets carry a ROLE per macro: 'about' (land near), 'atLeast'
// (a floor — only falling short matters), 'under' (a cap — only going over
// matters). Null role = the axis default: protein is a floor, everything
// else is 'about'. That default IS the product's minimal path — "target
// calories, protein is a floor" with zero extra taps.
void main() {
  late AppDatabase db;
  late TargetsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TargetsRepository(db);
  });

  tearDown(() => db.close());

  test('an untouched database has no targets and the default roles',
      () async {
    final t = await repo.get();
    expect(t.isSet, isFalse);
    expect(t.values, const MacroSet());
    expect(t.resolvedKcalRole, TargetRole.about);
    expect(t.resolvedProteinRole, TargetRole.atLeast,
        reason: 'protein defaults to a floor');
    expect(t.resolvedCarbRole, TargetRole.about);
    expect(t.resolvedFatRole, TargetRole.about);
  });

  test('explicit roles round-trip exactly', () async {
    await repo.set(const DailyTargets(
      values: MacroSet(kcal: 2000, proteinG: 150),
      kcalRole: TargetRole.under,
      proteinRole: TargetRole.atLeast,
    ));

    final t = await repo.get();
    expect(t.values.kcal, 2000);
    expect(t.values.proteinG, 150);
    expect(t.kcalRole, TargetRole.under);
    expect(t.proteinRole, TargetRole.atLeast);
    expect(t.carbRole, isNull, reason: 'unset roles stay unset');
    expect(t.resolvedCarbRole, TargetRole.about);
  });

  test('set is a full replace — clearing a slot really clears it', () async {
    await repo.set(const DailyTargets(
      values: MacroSet(kcal: 2000, carbG: 250),
      kcalRole: TargetRole.under,
    ));
    await repo.set(const DailyTargets(values: MacroSet(kcal: 1800)));

    final t = await repo.get();
    expect(t.values.kcal, 1800);
    expect(t.values.carbG, isNull);
    expect(t.kcalRole, isNull, reason: 'roles are replaced with the rest');
  });

  test('a row written before roles existed reads as null roles → defaults',
      () async {
    await db.customStatement(
        'INSERT INTO targets (id, kcal, protein_g) VALUES (1, 2200, 120)');

    final t = await repo.get();
    expect(t.values.kcal, 2200);
    expect(t.proteinRole, isNull);
    expect(t.resolvedProteinRole, TargetRole.atLeast);
  });

  test('an unrecognized stored role reads as null, never a crash', () async {
    await db.customStatement(
        "INSERT INTO targets (id, kcal, kcal_role) VALUES (1, 2000, 'zesty')");

    final t = await repo.get();
    expect(t.kcalRole, isNull);
    expect(t.resolvedKcalRole, TargetRole.about);
  });

  test('watch emits the new targets when they change', () async {
    final seen = <DailyTargets>[];
    final sub = repo.watch().listen(seen.add);
    addTearDown(sub.cancel);

    await repo.set(const DailyTargets(
        values: MacroSet(kcal: 2000), kcalRole: TargetRole.about));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(seen.last.values.kcal, 2000);
    expect(seen.last.kcalRole, TargetRole.about);
  });

  test('axes exposes each macro with its resolved role, for the engine',
      () async {
    const t = DailyTargets(
      values: MacroSet(kcal: 2000, proteinG: 150),
      kcalRole: TargetRole.under,
    );
    final byName = {for (final a in t.axes) a.axis: a};

    expect(byName.keys,
        containsAll(['kcal', 'protein', 'carbs', 'fat']));
    expect(byName['kcal']!.target, 2000);
    expect(byName['kcal']!.role, TargetRole.under);
    expect(byName['protein']!.role, TargetRole.atLeast);
    expect(byName['carbs']!.target, isNull);
    expect(
        byName['protein']!
            .of(const MacroSet(kcal: 1, proteinG: 2, carbG: 3, fatG: 4)),
        2,
        reason: 'each axis knows how to read itself out of a MacroSet');
  });
}
