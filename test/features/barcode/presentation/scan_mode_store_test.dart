import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/core/storage/app_database.dart';
import 'package:peckish/features/barcode/presentation/scan_mode_store.dart';

// Plain async tests (no widget zone), so drift futures resolve normally.
// The db is in-memory and simply dropped — closing mid-suite deadlocks.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));

  test('unset means null, so callers pick the platform default', () async {
    expect(await ScanModeStore(db).load(), isNull);
  });

  test('save/load round-trips both values on one row', () async {
    final store = ScanModeStore(db);
    await store.save(ScanMode.type);
    expect(await store.load(), ScanMode.type);
    await store.save(ScanMode.camera); // overwrite, not a second row
    expect(await store.load(), ScanMode.camera);
  });

  test('an unrecognized stored value is treated as unset', () async {
    // Pins the KV key while it is at it.
    await db.into(db.userPrefs).insertOnConflictUpdate(
        UserPrefsCompanion.insert(key: 'scan.mode', value: 'hologram'));
    expect(await ScanModeStore(db).load(), isNull);
  });
}
