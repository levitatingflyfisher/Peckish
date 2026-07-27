import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';
import 'package:peckish/features/sync/data/sync_secret_store.dart';
import 'package:peckish/features/sync/presentation/sync_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
void main() {
  late AppDatabase db;
  late InMemorySyncSecretStore secrets;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    secrets = InMemorySyncSecretStore();
  });

  Widget host() => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          syncSecretStoreProvider.overrideWithValue(secrets),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const SyncScreen()),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('no code yet: sync actions are gated until one exists',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Create a household code'), findsOneWidget);
    final syncNow =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Sync now'));
    expect(syncNow.onPressed, isNull,
        reason: 'no code means no pairing means nothing to sync with');
    await unmount(tester);
  });

  testWidgets('creating a code persists it and stamps existing rows',
      (tester) async {
    // A pre-sync row with no stamp: adopting a code must make it syncable.
    await tester.runAsync(() async {
      final repo = CustomFoodRepository(db);
      await repo.create(CustomFood(
        id: 'cf-1',
        name: 'Old row',
        servingLabel: '1',
        perServing: const MacroSet(kcal: 1),
        createdAt: DateTime(2026),
      ));
      // Wipe its stamp to simulate a row from before sync existed.
      await db.customStatement(
          'UPDATE custom_foods SET hlc = NULL, node_id = NULL');
    });

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Create a household code'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(secrets.lastWritten, isNotNull);
    expect(secrets.lastWritten!.length,
        greaterThanOrEqualTo(kMinSyncSecretLength));
    expect(find.textContaining('1 existing item'), findsOneWidget,
        reason: 'the backfill is visible, honest work');
    await unmount(tester);
  });
}
