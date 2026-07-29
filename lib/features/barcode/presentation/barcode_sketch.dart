import 'package:flutter/material.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// A hand-drawn UPC hint, pure canvas — no image asset to ship or theme.
///
/// Phone testing showed people type only the big middle digits: they don't
/// realize the small digits printed OUTSIDE the bars are part of the code
/// (and the checksum then rejects the number). So the sketch makes those
/// two small end digits the whole point, and the caption says it in words.
class BarcodeSketch extends StatelessWidget {
  const BarcodeSketch({super.key});

  static const caption =
      'Type all the numbers, including the small ones at the ends.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decorative; the caption below carries the meaning.
        ExcludeSemantics(
          child: SizedBox(
            width: 240,
            height: 84,
            child: CustomPaint(
              painter: _SketchPainter(
                barColor: scheme.outline,
                digitColor: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            caption,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({required this.barColor, required this.digitColor});

  final Color barColor;
  final Color digitColor;

  /// Alternating bar/space module widths — a plausible-looking pattern, not
  /// a real encoding (so nobody scans the hint).
  static const _modules = [
    1, 1, 1, 1, // left guard
    2, 1, 1, 2, 1, 3, 1, 1, 2, 1, 1, 1, 3, 1, 2, 1, //
    1, 1, 1, 1, // center guard
    1, 2, 1, 1, 3, 1, 1, 2, 1, 1, 2, 1, 1, 3, 1, 2, //
    1, 1, 1, // right guard
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Bars span the middle; the side insets exist to seat the small digits
    // OUTSIDE the bars, exactly like a printed UPC.
    const sideInset = 24.0;
    const barTop = 4.0;
    final barBottom = size.height - 22;
    final guardBottom = barBottom + 7; // guards dip into the digit row

    const left = sideInset;
    final span = size.width - 2 * sideInset;
    final totalModules = _modules.fold<int>(0, (a, b) => a + b);
    final moduleW = span / totalModules;

    final paint = Paint()..color = barColor;
    var x = left;
    for (var i = 0; i < _modules.length; i++) {
      final w = _modules[i] * moduleW;
      if (i.isEven) {
        // Guards (first, center pair, last) reach lower than data bars.
        final isGuard = i < 4 || (i >= 20 && i < 24) || i >= 40;
        canvas.drawRect(
          Rect.fromLTRB(x, barTop, x + w, isGuard ? guardBottom : barBottom),
          paint,
        );
      }
      x += w;
    }

    // Digit row: small first/last OUTSIDE the bars, big groups under them.
    final digitY = barBottom + 3;
    _digit(canvas, '0', Offset(sideInset / 2, digitY), 10);
    _digit(canvas, '12345', Offset(left + span * 0.28, digitY), 13);
    _digit(canvas, '67890', Offset(left + span * 0.72, digitY), 13);
    _digit(canvas, '5', Offset(size.width - sideInset / 2, digitY), 10);
  }

  void _digit(Canvas canvas, String text, Offset topCenter, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: digitColor,
          fontSize: fontSize,
          letterSpacing: 2,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, topCenter - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(_SketchPainter old) =>
      old.barColor != barColor || old.digitColor != digitColor;
}
