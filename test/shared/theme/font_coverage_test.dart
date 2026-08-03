import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/diary/presentation/day_format.dart';

// Peckish bundles its own type (Lora + Nunito) and does NOT fall back to a
// web font — that is the point of bundling. So any character the app prints
// has to be a character those files can actually draw; anything else is a
// tofu box on someone's phone, and whether it survives depends on an OS
// fallback chain we neither control nor ship.
//
// Found the hard way in v0.9: every target printed its role as ≤ or ≥, and
// neither font has either glyph. A whole release of "of □2200 kcal".
void main() {
  /// Every Unicode code point the font's cmap can draw.
  Set<int> coveredBy(String path) {
    final d = File(path).readAsBytesSync();
    final bytes = ByteData.view(Uint8List.fromList(d).buffer);
    final numTables = bytes.getUint16(4);
    int? cmapOffset;
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + 16 * i;
      final tag = String.fromCharCodes(d.sublist(rec, rec + 4));
      if (tag == 'cmap') cmapOffset = bytes.getUint32(rec + 8);
    }
    if (cmapOffset == null) return const {};

    final covered = <int>{};
    final numSubtables = bytes.getUint16(cmapOffset + 2);
    for (var i = 0; i < numSubtables; i++) {
      final rec = cmapOffset + 4 + 8 * i;
      final subtable = cmapOffset + bytes.getUint32(rec + 4);
      if (bytes.getUint16(subtable) != 4) continue; // format 4 only
      final segCount = bytes.getUint16(subtable + 6) ~/ 2;
      final endsAt = subtable + 14;
      final startsAt = endsAt + segCount * 2 + 2;
      for (var s = 0; s < segCount; s++) {
        final end = bytes.getUint16(endsAt + s * 2);
        final start = bytes.getUint16(startsAt + s * 2);
        if (end == 0xFFFF) continue; // the required terminator segment
        for (var c = start; c <= end; c++) {
          covered.add(c);
        }
      }
    }
    return covered;
  }


  /// True for code points a system emoji font will render regardless of what
  /// this app bundles: the pictographic planes, plus the zero-width joiner
  /// and variation selectors that glue emoji sequences together.
  bool isEmoji(int r) =>
      r >= 0x1F000 || r == 0x200D || (r >= 0xFE00 && r <= 0xFE0F);

  late Set<int> drawable;

  setUpAll(() {
    // The intersection: text can land in either family, so a character is
    // only safe if BOTH can draw it.
    drawable = coveredBy('assets/fonts/Nunito-Regular.ttf')
        .intersection(coveredBy('assets/fonts/Lora-Regular.ttf'));
  });

  void expectDrawable(String text, {required String where}) {
    final missing = [
      for (final r in text.runes)
        if (!drawable.contains(r)) '${String.fromCharCode(r)} '
            '(U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')})'
    ];
    expect(missing, isEmpty,
        reason: '$where prints ${missing.join(', ')}, which the bundled '
            'fonts cannot draw — it renders as a box');
  }

  test('the fonts really were loaded and parsed', () {
    // Guards the test itself: an empty coverage set would make every
    // assertion below vacuous in the wrong direction.
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

  test('no string literal anywhere in lib/ prints an undrawable character',
      () {
    // The general form of the ≤/≥ bug. Sweeping the source beats listing
    // the strings we happen to remember: the next em dash or arrow someone
    // reaches for gets caught the day it is typed, not the release after.
    final quoted = RegExp(r"'([^'\\\n]|\\.)*'|" r'"([^"\\\n]|\\.)*"');
    final offenders = <String, Set<String>>{};

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart'))) {
      for (final line in file.readAsLinesSync()) {
        // A string literal is not always display text. A character class
        // like [\s$€£¥₹¢] exists so a pasted price parses — it is never
        // drawn, and "fixing" it would break input. Patterns opt out here;
        // anything else needs the explicit marker.
        if (line.contains('RegExp(') || line.contains('// not-rendered')) {
          continue;
        }
        final code = line.trimLeft();
        if (code.startsWith('//')) continue; // prose, never rendered
        for (final m in quoted.allMatches(line)) {
          for (final r in m[0]!.runes) {
            // Emoji are exempt: every mobile OS renders them from a
            // dedicated colour-emoji font, so they are NOT drawn from ours
            // and do NOT box. Arrows, checks and currency signs have no
            // such guarantee — those are the ones that bite.
            if (r > 0x7F && !isEmoji(r) && !drawable.contains(r)) {
              offenders
                  .putIfAbsent(
                      '${String.fromCharCode(r)} '
                      '(U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')})',
                      () => <String>{})
                  .add(file.path);
            }
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these characters render as boxes in Lora/Nunito:\n'
            '${offenders.entries.map((e) => '  ${e.key} in ${e.value.join(', ')}').join('\n')}');
  });
}
