import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/features/ai/on_device/plate_scan.dart';
import 'package:peckish/features/ai/on_device/plate_scanner.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// Drift widget-test rules apply — see the canonical comment in
// test/features/groceries/presentation/groceries_screen_test.dart.
//
// Snap your plate, end to end minus hardware: a faked photo pick and a
// faked classifier drive the REAL label→spine→draft→confirm pipeline.
// The rung needs NO AI configuration — it's the classifier plus the
// bundled spine, so the tile exists on capable devices from first launch.
class _FakeScanner extends PlateScanner {
  _FakeScanner(this.labels);
  final List<DetectedLabel> labels;
  @override
  Future<List<DetectedLabel>> labelsOf(String imagePath) async => labels;
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.into(db.usdaFoods).insert(UsdaFoodsCompanion.insert(
          fdcId: const Value(1),
          source: 'sr',
          name: 'Pizza, cheese',
          nameNorm: 'pizza, cheese',
          kcal: const Value(266),
          proteinG: const Value(11.4),
        ));
    await db.into(db.usdaPortions).insert(UsdaPortionsCompanion.insert(
        fdcId: 1, label: '1 slice', grams: 107));
  });

  Widget host(List<DetectedLabel> labels) => ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          spineReadyProvider.overrideWith((ref) async {}),
          platePhotoPickerProvider
              .overrideWithValue(() async => '/fake/plate.jpg'),
          plateScannerProvider.overrideWithValue(_FakeScanner(labels)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const TodayScreen()),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    // The binding verifies foundation vars are pristine at test end.
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guess it for me'));
    await tester.pumpAndSettle();
  }

  testWidgets('the tile exists on a capable device with NO AI configured',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(host(const []));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Guess it for me'), findsOneWidget,
        reason: 'plate scanning is not an AI opt-in — no key, no download');
    await unmount(tester);
  });

  testWidgets('snap → classifier → spine drafts → confirm → the day',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(host(const [(label: 'Pizza', confidence: 0.9)]));
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Snap your plate'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.text('Pizza, cheese'), findsOneWidget,
        reason: 'the draft line is the SPINE food, real macros attached');
    expect(find.textContaining('confident'), findsOneWidget,
        reason: "the classifier's real confidence in plain words");

    await tester.runAsync(() async {
      await tester.tap(find.text('Log 1 entry'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Pizza, cheese'), findsWidgets,
        reason: 'confirmed lines land on Today');
    await unmount(tester);
  });

  testWidgets('a photo with nothing edible is a calm state', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester
        .pumpWidget(host(const [(label: 'Tableware', confidence: 0.98)]));
    await tester.pumpAndSettle();
    await openSheet(tester);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Snap your plate'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    expect(find.textContaining("Couldn't spot any food"), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    await unmount(tester);
  });

  testWidgets('no photo button, no tile, on an unsupported platform',
      (tester) async {
    // The test binding REPORTS android by default — be explicit here.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(host(const []));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Guess it for me'), findsNothing,
        reason: 'unconfigured AND no plate rung → the tile stays away');
    await unmount(tester);
  });
}
