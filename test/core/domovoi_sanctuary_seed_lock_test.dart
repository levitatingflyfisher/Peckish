import 'package:domovoi/domovoi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sanctuary_auth_core/sanctuary_auth_core.dart';

// THE CROSS-CONTRACT LOCK. sanctuary_auth_core (Flutter, the apps' spine)
// and domovoi (pure Dart, the stove CLI) each carry their OWN BIP39 seed
// derivation — they cannot share code (domovoi must stay Flutter-free,
// ADR-0001). This test is the only thing holding the two implementations
// together: if either ever drifts (different salt, iterations, hash, or
// normalization), every paired stove goes dark with "refused" and no
// other test in either repo will notice. It must never be deleted or
// loosened.
void main() {
  // A valid 12-word phrase (the standard BIP39 all-'abandon' vector).
  const phrase =
      'abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon about';

  test(
      'sanctuary and domovoi derive byte-identical seeds from the same '
      'household phrase', () async {
    final sanctuarySeed = await OpenHearthMnemonic.deriveSeed(phrase);
    final domovoiSeed = await DomovoiKeys.seedFromPhrase(phrase);

    expect(domovoiSeed, orderedEquals(sanctuarySeed));
  });

  test('both match the published BIP39 vector, not merely each other',
      () async {
    // PBKDF2-HMAC-SHA512(phrase, "mnemonic", 2048 iters, 64 bytes) with an
    // empty passphrase — independently computed (Python hashlib) and equal
    // to the widely published all-'abandon' seed. Guards against BOTH
    // implementations drifting in lockstep (a shared dependency bug).
    const vectorHex =
        '5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1'
        '9a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4';

    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    expect(hex(await OpenHearthMnemonic.deriveSeed(phrase)), vectorHex);
    expect(hex(await DomovoiKeys.seedFromPhrase(phrase)), vectorHex);
  });
}
