import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the dialog and returns the confirm FilledButton's resolved background.
Future<Color?> _confirmBackground(
  WidgetTester tester, {
  Color? confirmColor,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showConfirmDialog(
            context,
            title: 'T',
            message: 'M',
            confirmColor: confirmColor,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  final button = tester.widget<FilledButton>(
    find.ancestor(
      of: find.text('Delete'),
      matching: find.byType(FilledButton),
    ),
  );
  return button.style?.backgroundColor?.resolve(<WidgetState>{});
}

void main() {
  testWidgets('defaults the confirm button to clay, never red', (tester) async {
    final bg = await _confirmBackground(tester);
    expect(bg, AppColors.clay);
  });

  testWidgets('an explicit confirmColor is honoured', (tester) async {
    final bg = await _confirmBackground(tester, confirmColor: AppColors.sage);
    expect(bg, AppColors.sage);
  });
}
