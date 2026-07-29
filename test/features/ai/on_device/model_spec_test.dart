import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/on_device/model_spec.dart';

// The catalog is a TRUST boundary, and these are its laws (the Reckon
// lessons, kept as tests so they cannot regress):
//  * every artifact comes from the litert-community org — no personal
//    mirrors, ever, however convenient;
//  * everything is ungated — a nutrition parser must never demand a
//    HuggingFace token;
//  * no litert-lm URLs — flutter_gemma 0.13.2 loads ZIP .task bundles
//    only; raw "TFL3" flatbuffers die with "unable to open zip archive";
//  * a small (<800 MB) option exists, and it IS the default — parsing
//    "two eggs and toast" does not need a big model.
void main() {
  test('every model comes from the trusted org, ungated', () {
    expect(PeckishModelSpec.availableModels, isNotEmpty);
    for (final spec in PeckishModelSpec.availableModels) {
      expect(spec.downloadUrl,
          startsWith('https://huggingface.co/litert-community/'));
      expect(spec.downloadUrl.toLowerCase(), isNot(contains('litert-lm')),
          reason: 'TFL3 flatbuffers cannot be loaded by this MediaPipe');
      expect(spec.requiresToken, isFalse);
      expect(spec.sizeBytes, greaterThan(100 * 1024 * 1024));
    }
  });

  test('the default is the small Qwen — right-sized for a parser', () {
    final d = PeckishModelSpec.byId(null);
    expect(d.id, 'qwen-2.5-0.5b-it');
    expect(d.sizeBytes, lessThan(800 * 1024 * 1024));
    expect(PeckishModelSpec.availableModels.first, d,
        reason: 'the list leads with the default');
  });

  test('an unknown id falls back to the default, never crashes', () {
    expect(PeckishModelSpec.byId('gpt-99').id, 'qwen-2.5-0.5b-it');
  });

  test('model types are strings the builder maps by name', () {
    for (final spec in PeckishModelSpec.availableModels) {
      expect(spec.modelType, 'qwen',
          reason: 'the catalog is deliberately all-Qwen for now');
    }
  });
}
