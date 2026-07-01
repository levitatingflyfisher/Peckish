import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

void main() {
  late AppDatabase db;
  late CustomFoodRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CustomFoodRepository(db);
  });

  tearDown(() => db.close());

  CustomFood caferio() => CustomFood(
        id: 'cf-1',
        name: 'Cafe Rio grilled chicken salad (small)',
        servingLabel: '1 salad',
        perServing: const MacroSet(kcal: 640, proteinG: 42, carbG: 51, fatG: 29),
        createdAt: DateTime(2026, 7, 25),
      );

  test('create then read back preserves every field', () async {
    await repo.create(caferio());
    final got = await repo.byId('cf-1');
    expect(got!.name, contains('Cafe Rio'));
    expect(got.servingLabel, '1 salad');
    expect(got.perServing.kcal, 640);
    expect(got.perServing.proteinG, 42);
  });

  test('update edits in place — CRUD completeness is law', () async {
    await repo.create(caferio());
    await repo.update(caferio().copyWith(
      name: 'Cafe Rio salad, no dressing',
      perServing: const MacroSet(kcal: 520, proteinG: 42, carbG: 40, fatG: 18),
    ));
    final got = await repo.byId('cf-1');
    expect(got!.name, 'Cafe Rio salad, no dressing');
    expect(got.perServing.kcal, 520);
  });

  test('archive hides from the default list but keeps the row', () async {
    await repo.create(caferio());
    await repo.setArchived('cf-1', archived: true);
    expect(await repo.getAll(), isEmpty);
    expect(await repo.getAll(includeArchived: true), hasLength(1));
    // and it is reversible
    await repo.setArchived('cf-1', archived: false);
    expect(await repo.getAll(), hasLength(1));
  });

  test('delete removes the row entirely', () async {
    await repo.create(caferio());
    await repo.delete('cf-1');
    expect(await repo.byId('cf-1'), isNull);
    expect(await repo.getAll(includeArchived: true), isEmpty);
  });

  test('a food with only kcal known keeps the other slots null', () async {
    await repo.create(CustomFood(
      id: 'cf-2',
      name: 'Mystery church potluck plate',
      servingLabel: '1 plate',
      perServing: const MacroSet(kcal: 700),
      createdAt: DateTime(2026, 7, 25),
    ));
    final got = await repo.byId('cf-2');
    expect(got!.perServing.kcal, 700);
    expect(got.perServing.proteinG, isNull);
  });
}
