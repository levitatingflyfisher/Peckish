import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/diary/presentation/today_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';

import '../../../support/backup_overrides.dart';

/// At 320dp x 3.0 the Today title used to vanish: the bar gave all its
/// width to "Settings" and the theme word (rollout concern 2). The fleet's
/// fold-by-space row keeps the title whole and folds words into tooltips
/// only as far as it must.
void main() {
  for (final (width, scale) in const [(320.0, 3.0), (320.0, 2.0), (360.0, 1.3)]) {
    testWidgets('Today title stays whole at ${width}dp x $scale', (tester) async {
      tester.view.physicalSize = Size(width, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          spineReadyProvider.overrideWith((ref) async {}),
          ...backupTestOverrides(),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 700),
              textScaler: TextScaler.linear(scale),
            ),
            child: const TodayScreen(),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final title = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Today'),
      );
      expect(title, findsOneWidget);
      final p = tester.renderObject<RenderParagraph>(title);
      final whole = TextPainter(
        text: p.text,
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
        maxLines: 1,
      )..layout();
      expect(p.size.width, greaterThanOrEqualTo(whole.width - 0.5),
          reason: 'title squeezed to ${p.size.width} of ${whole.width}');
      expect(p.didExceedMaxLines, isFalse);
      whole.dispose();
      // Settings is still reachable by name (word or tooltip).
      expect(
        find.text('Settings').evaluate().isNotEmpty ||
            find.byTooltip('Settings').evaluate().isNotEmpty,
        isTrue,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await tester.runAsync(db.close);
    });
  }
}
