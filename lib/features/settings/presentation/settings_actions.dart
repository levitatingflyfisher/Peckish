// Destructive settings actions. Kept out of the widget so the erase path is a
// single, testable unit: wipe the tables, then refresh every keepAlive read
// model so no screen keeps showing pre-wipe data.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/recipes/data/recipe_draft_store.dart';

/// What "Erase all data" did.
enum EraseOutcome {
  /// A verified safety copy is in Previous backups; restoring it undoes the
  /// erase.
  erasedWithSafetyCopy,

  /// No recovery words, so no copy could be sealed; the person agreed in a
  /// dialog that said there is no way back.
  erasedNoCopy,

  /// The safety copy failed, so nothing was erased.
  keptBecauseSnapshotFailed,
}

/// The erase, behind sanctuary_backup_ui's pre-wipe snapshot: wipe only once
/// a verified copy of the current data is in the vault, never after the copy
/// failed. With no recovery words there is no copy to take, and the wipe goes
/// ahead only if the person was told so ([promisedCopy] false): someone who
/// agreed to an erase with a safety copy did not agree to one without.
/// (A seam over the two calls so the rule is testable on its own.)
Future<EraseOutcome> eraseAfterSnapshot({
  required Future<PreWipeSnapshot> Function() snapshot,
  required Future<void> Function() wipe,
  required bool promisedCopy,
}) async {
  final snap = await snapshot();
  switch (snap.outcome) {
    case PreWipeOutcome.taken:
      await wipe();
      return EraseOutcome.erasedWithSafetyCopy;
    case PreWipeOutcome.noKey:
      if (promisedCopy) return EraseOutcome.keptBecauseSnapshotFailed;
      await wipe();
      return EraseOutcome.erasedNoCopy;
    case PreWipeOutcome.failed:
      return EraseOutcome.keptBecauseSnapshotFailed;
  }
}

/// Erase all user data, recipe drafts included. Shell prefs (theme)
/// survive.
///
/// The provider-invalidation list below grows with the domain features
/// (diary, recipes, plan, groceries) in the same commit that adds their
/// keepAlive providers.
Future<void> eraseAllData(WidgetRef ref) async {
  await ref.read(appDatabaseProvider).eraseUserData();
  // Unsaved recipe drafts are the household's words too.
  await ref.read(recipeDraftStoreProvider).clearAll();
}

/// Mirrors [eraseAllData]'s provider-invalidation set, for the `Ref`-typed
/// hook `SanctuaryBackupConfig.onAfterRestore` runs after a destructive
/// encrypted-backup restore (SANCTUARY-BRIEF §4.W2). Not literally shared
/// with [eraseAllData]: that function is typed to `WidgetRef` (called from a
/// settings-screen `onTap`), which is a distinct type from the
/// `BackupController` Notifier's `Ref` — Riverpod gives them no common
/// supertype, so the invalidation list is duplicated here rather than shared.
Future<void> afterBackupRestore(Ref ref) async {
  // No domain read models yet — grows with the features.
}
