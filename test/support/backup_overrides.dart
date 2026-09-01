import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';
import 'package:sanctuary_backup_ui/testing.dart';

/// Overrides for any widget test that reaches Settings (or anything else
/// that mounts the backup section).
///
/// Since sanctuary_backup_ui 0.3.0 the section reads the key store and the
/// finish-setup reminder store as soon as it builds. On the platform plugin
/// those reads never answer in a widget test, so pumpAndSettle times out.
/// These are the package's own in-memory stand-ins.
List<Override> backupTestOverrides() => [
      secureKeyStoreProvider.overrideWithValue(InMemorySecureKeyStore()),
      backupReminderStoreProvider
          .overrideWithValue(InMemoryBackupReminderStore()),
    ];
