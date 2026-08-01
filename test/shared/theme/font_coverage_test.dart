import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oh_fleet_conformance/oh_fleet_conformance.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/presentation/day_format.dart';

// The general sweep — every string literal under lib/ — is C7 in the fleet
// conformance suite. What stays here is what a source sweep structurally
// cannot see: text Peckish BUILDS at runtime out of enum fields and table
// lookups, which never appears as a literal anywhere.
//
// That distinction is not academic. The v0.9 bug was exactly this shape:
// `TargetRole.mark` printed ≤ and ≥, neither of which Lora or Nunito can
// draw, and a whole release shipped reading "of □2200 kcal".
void main() {
  late Set<int> drawable;

  setUpAll(() => drawable = bundledFontCoverage(root: Directory.current));

  void expectDrawable(String text, {required String where}) {
    expect(undrawableIn(text, drawable), isEmpty,
        reason: '$where prints characters the bundled fonts cannot draw — '
            'they render as boxes');
  }

  test('the coverage really was read', () {
    // Without this the assertions below would pass for free against an
    // empty set, which is the wrong direction to fail in.
    expect(drawable.length, greaterThan(200));
    expect(drawable, contains(0x00B7), reason: '· is used in every day label');
  });

  test('every target role mark is drawable', () {
    for (final role in TargetRole.values) {
      expectDrawable(role.mark, where: 'TargetRole.${role.name}.mark');
    }
  });

  test('the day labels are drawable', () {
    expectDrawable(prettyDay('2026-08-13'), where: 'prettyDay');
    for (final m in monthFullNames) {
      expectDrawable(m, where: 'monthFullNames');
    }
    for (final l in weekdayLetters) {
      expectDrawable(l, where: 'weekdayLetters');
    }
  });
}
