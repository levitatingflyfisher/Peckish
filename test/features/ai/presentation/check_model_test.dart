import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/data/ai_config_repository.dart';
import 'package:peckish/features/ai/data/stove_secret_store.dart';
import 'package:peckish/features/ai/on_device/local_brain.dart';
import 'package:peckish/features/ai/on_device/model_download_service_io.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/features/ai/presentation/ai_settings_dialog.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart'
    show aiConfigRepositoryProvider;
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A "Check the model" action in the AI dialog: runs a tiny canned prompt
// through the resident model and shows a copyable result block. This is
// the field-test lesson — "local model definitely just doesn't work at
// all" came back with nothing more to go on than that sentence.
//
// [GemmaLocalBrain]'s OWN checkModel() correctness (pass, a real failure
// message, which backend answered after a GPU→CPU fallback) is proven in
// gemma_brain_test.dart, in plain test()s. Widget tests here fake at the
// [ModelDiagnostics] interface boundary instead of constructing a real
// GemmaLocalBrain — flutter_gemma's InferenceChat machinery does not
// return control under TestWidgetsFlutterBinding (confirmed by hand: the
// identical fake-session setup that answers in ~20ms under plain test()
// in gemma_brain_test.dart never completes under testWidgets(), with or
// without runAsync). This is the "plugin can't run under flutter_test —
// fake at the interface boundary" instruction, taken literally: the
// interface is ModelDiagnostics, not flutter_gemma's own classes.

class _MemoryKeys implements KeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async => value = v;
}

class _FakeDiagnosticsBrain implements LocalBrain, ModelDiagnostics {
  _FakeDiagnosticsBrain(this._result);
  final ModelCheckResult _result;

  @override
  Future<String> complete(String prompt) async => 'unused in these tests';

  @override
  Future<ModelCheckResult> checkModel() async => _result;
}

class _InstantAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = Uint8List(2 * 1024 * 1024);
    return ResponseBody.fromBytes(body, 200, headers: {
      Headers.contentLengthHeader: ['${body.length}'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tempDir;
  late ModelDownloadService downloads;
  late AiConfigRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('peckish_check_model_test');
    downloads = ModelDownloadService(
      dio: Dio()..httpClientAdapter = _InstantAdapter(),
      documentsDirectory: () async => tempDir,
    );
    SharedPreferences.setMockInitialValues({});
    repo = AiConfigRepository(await SharedPreferences.getInstance(),
        _MemoryKeys(), InMemoryStoveSecretStore());
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Widget host(LocalBrain? brain) => ProviderScope(
        overrides: [
          aiConfigRepositoryProvider.overrideWithValue(repo),
          modelDownloadServiceProvider.overrideWithValue(downloads),
          localBrainProvider.overrideWithValue(brain),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: TextButton(
                  onPressed: () => showAiSettingsDialog(context, ref),
                  child: const Text('open ai settings'),
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> openOnDeviceSection(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('open ai settings'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('On this phone'));
      // the section's isDownloaded probes are real file I/O
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('Check the model reports pass, elapsed, backend, model, abi',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final brain = _FakeDiagnosticsBrain(const ModelCheckResult(
      ok: true,
      elapsed: Duration(milliseconds: 42),
      backend: 'gpu',
      modelId: 'qwen-2.5-0.5b-it',
      abi: 'android_arm64',
    ));
    await tester.pumpWidget(host(brain));
    await tester.pumpAndSettle();
    await openOnDeviceSection(tester);

    expect(find.text('Check the model'), findsOneWidget);
    await tester.ensureVisible(find.text('Check the model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check the model'));
    await tester.pumpAndSettle();

    // A plain sentence first (fleet error ruling); the copyable block is
    // the detail behind it.
    expect(find.textContaining('The model works'), findsOneWidget);
    expect(find.textContaining('pass: true'), findsNothing);
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pass: true'), findsOneWidget);
    expect(find.textContaining('elapsed: 42ms'), findsOneWidget);
    expect(find.textContaining('backend: gpu'), findsOneWidget);
    expect(find.textContaining('model: qwen-2.5-0.5b-it'), findsOneWidget);
    expect(find.textContaining('abi: android_arm64'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a failing check shows the real error, glyph-safe',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final brain = _FakeDiagnosticsBrain(const ModelCheckResult(
      ok: false,
      elapsed: Duration(milliseconds: 12),
      backend: 'cpu-fallback',
      modelId: 'qwen-2.5-0.5b-it',
      abi: 'android_arm64',
      error: 'Exception: native crash',
    ));
    await tester.pumpWidget(host(brain));
    await tester.pumpAndSettle();
    await openOnDeviceSection(tester);

    await tester.ensureVisible(find.text('Check the model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check the model'));
    await tester.pumpAndSettle();

    // The raw exception is never the first thing on screen: a sentence
    // says what happened, and Details holds the real error to copy.
    expect(find.textContaining('didn’t answer'), findsOneWidget);
    expect(find.textContaining('native crash'), findsNothing);
    await tester.ensureVisible(find.text('Details'));
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pass: false'), findsOneWidget);
    expect(find.textContaining('native crash'), findsOneWidget,
        reason: 'the real underlying error, not a re-hash of the calm '
            'guess-box copy');
    await unmount(tester);
  });

  testWidgets('no diagnostics tile when there is no on-device brain at all',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(host(null));
    await tester.pumpAndSettle();
    await openOnDeviceSection(tester);

    expect(find.text('Check the model'), findsNothing);
    await unmount(tester);
  });
}
