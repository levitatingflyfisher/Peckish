import 'package:flutter/material.dart';

/// Parses a user-typed number, accepting the comma decimal ('1,5') half the
/// world's keyboards produce alongside '1.5'. Junk and empty come back null —
/// an unfilled box simply isn't a number, never a zero.
double? parseFlexibleDouble(String text) =>
    double.tryParse(text.replaceAll(',', '.'));

/// The one decimal-entry field behind every macro/qty box: decimal keyboard,
/// comma-tolerant when read back through [parseFlexibleDouble]. [outlined]
/// keeps each dialog's existing look (underline in the quick-add and food
/// dialogs, outlined boxes in the targets and fix-line editors).
class NumField extends StatelessWidget {
  const NumField({
    super.key,
    required this.controller,
    required this.label,
    this.outlined = false,
  });

  final TextEditingController controller;
  final String label;
  final bool outlined;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: outlined ? const OutlineInputBorder() : null,
        ),
      );
}
