import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/barcode/presentation/barcode_sketch.dart';
import 'package:peckish/shared/theme/app_theme.dart';

// The sketch is pure canvas (no image asset), so the tests pin what a
// screenshot can't on CI: it renders in both themes, carries its teaching
// caption, and stays inside the compact height budget.
void main() {
  Widget host(ThemeData theme) => MaterialApp(
        theme: theme,
        home: const Scaffold(body: Center(child: BarcodeSketch())),
      );

  testWidgets('shows the caption about the small digits at the ends',
      (tester) async {
    await tester.pumpWidget(host(AppTheme.light));
    expect(find.textContaining('small ones at the ends'), findsOneWidget);
  });

  testWidgets('the painted bars stay inside the 72-96px height budget',
      (tester) async {
    await tester.pumpWidget(host(AppTheme.light));
    final canvas = find.descendant(
        of: find.byType(BarcodeSketch), matching: find.byType(CustomPaint));
    final height = tester.getSize(canvas).height;
    expect(height, inInclusiveRange(72, 96));
  });

  testWidgets('renders under the dark theme too', (tester) async {
    await tester.pumpWidget(host(AppTheme.dark));
    expect(find.byType(BarcodeSketch), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
