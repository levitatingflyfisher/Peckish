import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/data/saved_meal_repository.dart';
import 'package:peckish/features/diary/domain/saved_meal.dart';
import 'package:peckish/features/plan/data/plan_repository.dart';
import 'package:peckish/features/plan/domain/plan_entry.dart';
import 'package:peckish/features/recipes/data/recipe_repository.dart';
import 'package:peckish/features/recipes/domain/recipe.dart';

void main() {
  late AppDatabase db;
  late PlanRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = PlanRepository(db);
    await RecipeRepository(db).create(Recipe(
      id: 'r-1',
      title: 'Weeknight Tacos',
      servings: 4,
      createdAt: DateTime(2026, 7, 25),
    ));
    await SavedMealRepository(db).create(SavedMeal(
      id: 'm-1',
      name: 'Panda — bad day',
      position: 0,
      createdAt: DateTime(2026, 7, 25),
      items: const [],
    ));
  });

  tearDown(() => db.close());

  test('a planned recipe resolves its live title', () async {
    await repo.upsert(const PlanEntry(
      id: 'p-1',
      day: '2026-07-27',
      slot: PlanSlot.dinner,
      kind: PlanKind.recipe,
      refId: 'r-1',
    ));
    final week = await repo.entriesForDays(['2026-07-27']);
    expect(week.single.title, 'Weeknight Tacos');
    expect(week.single.kind, PlanKind.recipe);
  });

  test('staples and notes plan too — leftovers are first-class', () async {
    await repo.upsert(const PlanEntry(
      id: 'p-2',
      day: '2026-07-28',
      slot: PlanSlot.dinner,
      kind: PlanKind.meal,
      refId: 'm-1',
    ));
    await repo.upsert(const PlanEntry(
      id: 'p-3',
      day: '2026-07-29',
      slot: PlanSlot.dinner,
      kind: PlanKind.note,
      note: 'Leftovers',
    ));
    final week = await repo.entriesForDays(['2026-07-28', '2026-07-29']);
    expect(week.map((e) => e.title).toList(), ['Panda — bad day', 'Leftovers']);
  });

  test('upsert with the same id moves the entry (drag to another day)',
      () async {
    await repo.upsert(const PlanEntry(
      id: 'p-1',
      day: '2026-07-27',
      slot: PlanSlot.dinner,
      kind: PlanKind.recipe,
      refId: 'r-1',
    ));
    await repo.upsert(const PlanEntry(
      id: 'p-1',
      day: '2026-07-28',
      slot: PlanSlot.lunch,
      kind: PlanKind.recipe,
      refId: 'r-1',
    ));
    expect(await repo.entriesForDays(['2026-07-27']), isEmpty);
    final moved = (await repo.entriesForDays(['2026-07-28'])).single;
    expect(moved.slot, PlanSlot.lunch);
  });

  test('remove deletes the slot entry only', () async {
    await repo.upsert(const PlanEntry(
      id: 'p-1',
      day: '2026-07-27',
      slot: PlanSlot.dinner,
      kind: PlanKind.recipe,
      refId: 'r-1',
    ));
    await repo.remove('p-1');
    expect(await repo.entriesForDays(['2026-07-27']), isEmpty);
    // the recipe itself is untouched
    expect(await RecipeRepository(db).byId('r-1'), isNotNull);
  });

  test('a plan entry whose recipe was deleted shows a graceful title',
      () async {
    await repo.upsert(const PlanEntry(
      id: 'p-1',
      day: '2026-07-27',
      slot: PlanSlot.dinner,
      kind: PlanKind.recipe,
      refId: 'r-1',
    ));
    await RecipeRepository(db).delete('r-1');
    final entry = (await repo.entriesForDays(['2026-07-27'])).single;
    expect(entry.title, '(deleted recipe)');
  });
}
