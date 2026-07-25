// Destructive settings actions. Kept out of the widget so the erase path is a
// single, testable unit: wipe the tables, then refresh every keepAlive read
// model so no screen keeps showing pre-wipe data.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';

/// Erase all user data. Shell prefs (theme) survive.
///
/// The provider-invalidation list below grows with the domain features
/// (diary, recipes, plan, groceries) in the same commit that adds their
/// keepAlive providers.
Future<void> eraseAllData(WidgetRef ref) async {
  await ref.read(appDatabaseProvider).eraseUserData();
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
