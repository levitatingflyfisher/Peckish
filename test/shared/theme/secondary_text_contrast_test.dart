import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// dmmt-01 (lens audit 2026-09-16): every instructional sentence in the app,
/// the one line per screen that tells a new household what to do, was set
/// in stone (linen500) on flour at 3.86:1. Secondary text now comes from
/// ohStyle's textSecondary role, which is built to clear 4.5:1 on every
/// ground of its theme; stone stays for marks (icons, borders, rules).
void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('secondary text clears 4.5:1 in the $name theme',
        (tester) async {
      late Color secondary;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (context) {
          secondary = AppColors.secondaryText(context);
          return const SizedBox();
        }),
      ));
      for (final ground in [
        theme.scaffoldBackgroundColor,
        theme.cardTheme.color ?? theme.colorScheme.surface,
      ]) {
        expect(_contrast(secondary, ground), greaterThanOrEqualTo(4.5),
            reason: '$name secondary text on $ground');
      }
    });
  }

  test('no text style is painted in stone', () {
    // Stone is a mark colour now. A TextStyle.copyWith naming it (directly
    // or in a conditional) is text at 3.86:1 again.
    final inCopyWith = RegExp(r'copyWith\([^;]*?AppColors\.stone\b');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in inCopyWith.allMatches(f.readAsStringSync())) {
        // Only the copyWith's own arguments: stop at its closing paren.
        var depth = 0;
        final body = m.group(0)!;
        var inside = true;
        for (var i = body.indexOf('(');
            i < body.length;
            i++) {
          if (body[i] == '(') depth++;
          if (body[i] == ')') depth--;
          if (depth == 0) {
            inside = body.substring(i).contains('AppColors.stone') == false;
            break;
          }
        }
        if (inside) offenders.add('${f.path}: ${body.split('\n').first}');
      }
    }
    expect(offenders, isEmpty);
  });
}
