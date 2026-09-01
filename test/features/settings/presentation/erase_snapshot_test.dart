import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/settings/presentation/settings_actions.dart';
import 'package:sanctuary_backup_ui/sanctuary_backup_ui.dart';

// sanctuary_backup_ui 0.3.0: before "Erase all data" deletes anything, a
// verified safety snapshot of the current data goes into Previous backups,
// so the erase can be rolled back by an ordinary restore. Wipe only when the
// snapshot was taken; never when it failed. With no recovery words there is
// nothing to seal a snapshot under, and the person has already agreed, in a
// dialog that says so, that there is no way back.
void main() {
  Future<(EraseOutcome, bool)> run(PreWipeOutcome outcome,
      {bool promisedCopy = false}) async {
    var wiped = false;
    final result = await eraseAfterSnapshot(
      snapshot: () async => (outcome: outcome, entry: null),
      wipe: () async => wiped = true,
      promisedCopy: promisedCopy,
    );
    return (result, wiped);
  }

  test('a taken snapshot lets the erase go ahead', () async {
    expect(await run(PreWipeOutcome.taken),
        (EraseOutcome.erasedWithSafetyCopy, true));
  });

  test('a failed snapshot erases nothing', () async {
    expect(await run(PreWipeOutcome.failed),
        (EraseOutcome.keptBecauseSnapshotFailed, false));
  });

  test('no recovery words: the erase the person agreed to goes ahead',
      () async {
    expect(await run(PreWipeOutcome.noKey), (EraseOutcome.erasedNoCopy, true));
  });

  test('no key after the dialog promised a copy: nothing is erased',
      () async {
    // The person agreed to an erase with a safety copy, not to one with no
    // way back; the words vanishing in between must not change that.
    expect(await run(PreWipeOutcome.noKey, promisedCopy: true),
        (EraseOutcome.keptBecauseSnapshotFailed, false));
  });
}
