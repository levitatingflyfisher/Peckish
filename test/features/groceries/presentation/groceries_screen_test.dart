import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/groceries/data/grocery_repository.dart';
import 'package:peckish/features/groceries/presentation/groceries_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Widget-test rules for drift-backed screens (learned the hard way):
// 1. Seed data ONLY via tester.runAsync BEFORE pumpWidget — drift futures
//    complete on Timers and the fake clock only moves on pump().
// 2. Assert on UI STATE, never by awaiting db reads mid-test — cross-zone
//    drift calls can deadlock on drift's internal lock.
// 3. Don't close the db; unmount and pump past drift's stream keep-alive
//    timer instead (closing while anything is live deadlocks).

Widget host(AppDatabase db) => ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(theme: AppTheme.light, home: const GroceriesScreen()),
    );

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  testWidgets('typing into the add field adds a manual item and clears',
      (tester) async {
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Birthday candles');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Exactly one: the list row. The add field cleared itself.
    expect(find.text('Birthday candles'), findsOneWidget);
    expect(find.text('Everything else'), findsOneWidget); // aisle header
    await unmount(tester);
  });

  testWidgets('tapping an item checks it off (UI state)', (tester) async {
    await tester.runAsync(() => GroceryRepository(db).addManual('Milk'));
    await tester.pumpWidget(host(db));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);
    await tester.tap(find.text('Milk'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
    await unmount(tester);
  });
}
