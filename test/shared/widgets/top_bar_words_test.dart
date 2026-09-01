import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Fleet ruling on top bars: icon plus a short visible word; a tooltip is
// never a command's only name (a thumb never sees one). C11 accepts a
// tooltip as the floor; this holds Peckish to the ruling itself: no bare
// IconButton among any AppBar's actions.
void main() {
  test('no app-bar action is an icon alone', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final m in RegExp(r'actions:\s*(const\s*)?\[').allMatches(src)) {
        // Walk to the matching bracket.
        var depth = 0, i = m.end - 1;
        for (; i < src.length; i++) {
          if (src[i] == '[') depth++;
          if (src[i] == ']' && --depth == 0) break;
        }
        final body = src.substring(m.end, i);
        // Only AppBar actions: dialogs also take `actions:`.
        final before = src.substring(0, m.start);
        final owner = RegExp(r'(AppBar|AlertDialog|SnackBar|MaterialBanner)\(')
            .allMatches(before)
            .lastOrNull
            ?.group(1);
        if (owner != 'AppBar') continue;
        if (RegExp(r'\bIconButton(\.\w+)?\(').hasMatch(body)) {
          final line = '\n'.allMatches(before).length + 1;
          offenders.add('${f.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
