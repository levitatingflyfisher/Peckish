import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// House style for words on screen: no spaced em dashes, and typographic
/// apostrophes and quotes (’ “ ”) rather than typewriter ones (' ").
/// A source scan over string literals in lib/: comments, imports and log
/// lines are ignored. (Same scan as Sundial's and Furrow's; the fleet has no
/// shared home for it yet.) Two files are exempt because their quotes are
/// syntax, not copy: the schema.org parser's HTML regexes and entity
/// table, and the sync clock's SQL.
const _exempt = [
  'schema_org_recipe_parser.dart',
  'sync_clock.dart',
];

void main() {
  final literal = RegExp(r'"([^"\\]|\\.)*"' "|" r"'([^'\\]|\\.)*'");

  Iterable<(String, int, String)> literals() sync* {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .where((f) => !_exempt.any(f.path.endsWith));
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final t = line.trimLeft();
        if (t.startsWith('//') || line.contains('debugPrint(')) continue;
        if (t.startsWith('import ') || t.startsWith('export ')) continue;
        if (t.startsWith('part ')) continue;
        for (final m in literal.allMatches(line)) {
          yield (f.path, i + 1, m.group(0)!);
        }
      }
    }
  }

  test('no spaced em dash in on-screen copy', () {
    final hits = [
      for (final (path, line, lit) in literals())
        if (lit.contains(' — ') || lit.endsWith(" —'") || lit.endsWith(' —"'))
          '$path:$line $lit',
    ];
    expect(hits, isEmpty);
  });

  test('no typewriter apostrophe or quote inside on-screen copy', () {
    final apostrophe = RegExp(r"[A-Za-z]'[A-Za-z]");
    final escaped = RegExp(r"[A-Za-z}]\\'[A-Za-z]");
    final hits = [
      for (final (path, line, lit) in literals())
        if ((lit.startsWith('"') &&
                apostrophe.hasMatch(lit.substring(1, lit.length - 1))) ||
            (lit.startsWith("'") &&
                (lit.substring(1, lit.length - 1).contains('"') ||
                    escaped.hasMatch(lit))))
          '$path:$line $lit',
    ];
    expect(hits, isEmpty);
  });
}
