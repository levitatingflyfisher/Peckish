import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/settings/presentation/settings_screen.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

// The erase dialog must tell the truth about the way back, read from the
// key store at the moment it opens (not from whatever another screen left
// cached): with recovery words a verified safety copy is taken first; with
// none, there is no copy, and it says so.
void main() {
  const phrase = 'abandon abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon about';

  Future<void> openErase(WidgetTester tester, SecureKeyStore store) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(
            AppDatabase(NativeDatabase.memory())),
        secureKeyStoreProvider.overrideWithValue(store),
        backupReminderStoreProvider
            .overrideWithValue(InMemoryBackupReminderStore()),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Erase all data'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.ensureVisible(find.text('Erase all data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase all data'));
    // The dialog waits on a fresh read of the key store (and, with words,
    // the key derivation behind it), which runs on real time.
    for (var i = 0; i < 40 && find.byType(AlertDialog).evaluate().isEmpty;
        i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('without recovery words it says there is no copy',
      (tester) async {
    await openErase(tester, InMemorySecureKeyStore());
    expect(find.textContaining('there is no copy to restore'), findsOneWidget);
    expect(find.textContaining('safety copy'), findsNothing);
    await unmount(tester);
  });

  testWidgets('with recovery words it promises the safety copy',
      (tester) async {
    await openErase(
        tester, InMemorySecureKeyStore(mnemonic: phrase, acknowledged: true));
    expect(find.textContaining('safety copy is saved to Previous backups'),
        findsOneWidget);
    expect(find.textContaining('no copy'), findsNothing);
    await unmount(tester);
  });
}
