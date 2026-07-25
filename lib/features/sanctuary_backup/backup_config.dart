import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import '../settings/presentation/settings_actions.dart';

/// Peckish's [SanctuaryBackupConfig] — app identity, AEAD context, and the
/// destructive-restore consequence copy for the encrypted-backup wiring
/// (SANCTUARY-BRIEF §4.W2). Pulled out of `main.dart` into its own file so
/// the restore-consequence copy is unit-testable directly: it must list
/// everything a restore actually wipes (`AppDatabase.eraseUserData`'s
/// table set), and both grow together as the domain schema lands.
const peckishBackupConfig = SanctuaryBackupConfig(
  appId: 'peckish',
  aadContext: 'peckish-backup/v1',
  appDisplayName: 'Peckish',
  restoreReplaceConsequence:
      'Restoring will delete all Peckish data on this device, then replace '
      'it with the contents of the backup file.',
  onAfterRestore: _afterRestore,
);

// Fire-and-forget: the UI doesn't block on invalidation finishing (mirrors
// the fleet's onAfterRestore pattern of wrapping the async tail in
// unawaited()). afterBackupRestore itself returns a Future so it stays
// directly awaitable in tests.
void _afterRestore(Ref ref) => unawaited(afterBackupRestore(ref));
