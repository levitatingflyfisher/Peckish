import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/targets_repository.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

void main() {
  late AppDatabase db;
  late TargetsRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = TargetsRepository(db);
  });

  tearDown(() => db.close());

  test('unset targets read back as all-null (no targets, no judgement)',
      () async {
    final t = await repo.get();
    expect(t.kcal, isNull);
    expect(t.proteinG, isNull);
  });

  test('set then get round-trips; static numbers, no adaptive loop', () async {
    await repo.set(const MacroSet(kcal: 3200, proteinG: 180));
    final t = await repo.get();
    expect(t.kcal, 3200);
    expect(t.proteinG, 180);
    expect(t.carbG, isNull);
  });

  test('re-setting replaces, including back to null', () async {
    await repo.set(const MacroSet(kcal: 3200, proteinG: 180));
    await repo.set(const MacroSet(kcal: 2800));
    final t = await repo.get();
    expect(t.kcal, 2800);
    expect(t.proteinG, isNull);
  });
}
