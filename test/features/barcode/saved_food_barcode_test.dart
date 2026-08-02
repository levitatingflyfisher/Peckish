import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/barcode/data/barcode_resolver.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/food/data/custom_food_repository.dart';
import 'package:peckish/features/food/domain/custom_food.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

// "I entered a barcode twice in a row and the second time it looked it up
// again even though I said to save the food."
//
// Saving a scanned food promises "so next time is one tap". That promise is
// only kept if the code itself comes home with the food — otherwise the
// household's own answer is invisible to the very next scan, and Peckish
// asks the network a question it already knows the answer to.
void main() {
  late AppDatabase db;
  late CustomFoodRepository repo;
  final code = BarcodeCode.tryParse('027000612323')!;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = CustomFoodRepository(db);
  });

  tearDown(() => db.close());

  CustomFood spam({String? barcode, bool archived = false}) => CustomFood(
        id: 'spam',
        name: 'Spam',
        servingLabel: '2 slices',
        perServing: const MacroSet(kcal: 360, proteinG: 14),
        createdAt: DateTime(2026, 8, 1),
        archived: archived,
        barcode: barcode,
      );

  group('the food remembers its code', () {
    test('a saved food is findable by the barcode it came from', () async {
      await repo.create(spam(barcode: '027000612323'));

      final found = await repo.byBarcode('027000612323');

      expect(found?.name, 'Spam');
      expect(found?.perServing.kcal, 360);
    });

    test('the same product in any of its GTIN paddings is the same food',
        () async {
      // ADR-0010's normalization law reaches the household's own foods too:
      // a UPC-A saved off a tin must answer the EAN-13 the camera reads.
      await repo.create(spam(barcode: '027000612323'));

      expect((await repo.byBarcode('0027000612323'))?.name, 'Spam');
      expect((await repo.byBarcode('27000612323'))?.name, 'Spam');
    });

    test('a food saved without a code is not findable by one', () async {
      await repo.create(spam());

      expect(await repo.byBarcode('027000612323'), isNull);
    });

    test('a deleted food stops answering its code', () async {
      await repo.create(spam(barcode: '027000612323'));
      await repo.delete('spam');

      expect(await repo.byBarcode('027000612323'), isNull);
    });

    test('a resting food still answers — archiving hides it from pickers, '
        'and a scan is not a picker', () async {
      await repo.create(spam(barcode: '027000612323', archived: true));

      expect((await repo.byBarcode('027000612323'))?.name, 'Spam');
    });

    test('the code is stored in its one normalized form', () async {
      await repo.create(spam(barcode: '027000612323'));

      final all = await repo.getAll();

      // Normalized on the way in, so every read is a plain equality and
      // two paddings of one product can never become two foods.
      expect(all.single.barcode, '27000612323');
    });
  });

  group('the resolver asks the household first', () {
    test('a saved food answers before any slice is even consulted', () async {
      var slicesConsulted = false;
      final resolver = BarcodeResolver(
        installedDbPath: (_) async {
          slicesConsulted = true;
          return null;
        },
        savedFood: (c) async => spam(barcode: c.value),
      );

      final resolution = await resolver.resolveLocal(code);

      expect(resolution, isA<BarcodeSavedFood>());
      expect((resolution as BarcodeSavedFood).food.name, 'Spam');
      expect(slicesConsulted, isFalse,
          reason: 'your own answer is the cheapest one there is');
    });

    test('no saved food falls through to the slices, as before', () async {
      final resolver = BarcodeResolver(
        installedDbPath: (_) async => null,
        savedFood: (_) async => null,
      );

      expect(await resolver.resolveLocal(code), isA<BarcodeMiss>());
    });

    test('a broken saved-food lookup is a fall-through, never a crash',
        () async {
      final resolver = BarcodeResolver(
        installedDbPath: (_) async => null,
        savedFood: (_) async => throw StateError('database went away'),
      );

      expect(await resolver.resolveLocal(code), isA<BarcodeMiss>());
    });

    test('a resolver with no saved-food seam still works', () async {
      final resolver = BarcodeResolver(installedDbPath: (_) async => null);

      expect(await resolver.resolveLocal(code), isA<BarcodeMiss>());
    });
  });
}
