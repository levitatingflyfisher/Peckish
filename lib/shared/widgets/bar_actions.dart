import 'package:flutter/material.dart';

/// A top bar's actions, each an icon plus a short word (fleet ruling).
///
/// Two labelled actions only fit a 320dp bar up to 2x text, so the labels
/// stop growing there; the page itself scales fully (the Mantle precedent).
/// Without the cap the bar overflows at 320dp × 3.0.
class BarActions extends StatelessWidget {
  const BarActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 2.0,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
}
