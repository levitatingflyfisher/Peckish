import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/shared/widgets/num_field.dart';

// The shared decimal-entry pair: a comma-tolerant parse and the TextField
// every macro/qty box is built from (quick add, edit food, targets,
// fix-this-line).
void main() {
  group('parseFlexibleDouble', () {
    test('accepts the dot decimal', () {
      expect(parseFlexibleDouble('1.5'), 1.5);
      expect(parseFlexibleDouble('249'), 249);
    });

    test('accepts the comma decimal half the world types', () {
      expect(parseFlexibleDouble('1,5'), 1.5);
      expect(parseFlexibleDouble('0,75'), 0.75);
    });

    test('junk is null, never zero', () {
      expect(parseFlexibleDouble('abc'), isNull);
      expect(parseFlexibleDouble('1.2.3'), isNull);
    });

    test('empty is null — an unfilled box is not a number', () {
      expect(parseFlexibleDouble(''), isNull);
    });
  });

  group('NumField', () {
    testWidgets('shows a decimal keyboard and the given label', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NumField(controller: controller, label: 'kcal'),
        ),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.keyboardType,
          const TextInputType.numberWithOptions(decimal: true));
      expect(find.text('kcal'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1,5');
      expect(parseFlexibleDouble(controller.text), 1.5);
    });

    testWidgets('outlined switches the border, nothing else', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NumField(controller: controller, label: 'Qty', outlined: true),
        ),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.border, isA<OutlineInputBorder>());
    });
  });
}
