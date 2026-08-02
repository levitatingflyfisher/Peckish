import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/ai_config_repository.dart';
import 'package:peckish/features/ai/data/stove_secret_store.dart';
import 'package:peckish/features/ai/on_device/model_download_service_io.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/features/ai/presentation/ai_settings_dialog.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The on-device tier in Settings: an 'On this phone' choice with a small
// model manager — download once (resumable), pick, delete. The radio only
// exists where a model can actually run; saving stores the chosen model
// id in the config's model slot.
class _MemoryKeys implements KeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async => value = v;
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
    tempDir = await Directory.systemTemp.createTemp('peckish_dialog_test');
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

  Widget host() => ProviderScope(
        overrides: [
          aiConfigRepositoryProvider.overrideWithValue(repo),
          modelDownloadServiceProvider.overrideWithValue(downloads),
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

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('open ai settings'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('the radio exists only where a model can run', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await open(tester);
    expect(find.text('On this phone'), findsNothing);
    await unmount(tester);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await open(tester);
    expect(find.text('On this phone'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('picking it shows the catalog; download flows to Downloaded',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await open(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('On this phone'));
      // the section's isDownloaded probes are real file I/O
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('Qwen 2.5 0.5B'), findsOneWidget);
    expect(find.textContaining('Qwen 2.5 1.5B'), findsOneWidget);
    expect(find.text('Download'), findsNWidgets(2));

    await tester.runAsync(() async {
      await tester.tap(find.text('Download').first);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    expect(find.text('Downloaded'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('save persists the backend and the chosen model id',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.runAsync(() async {
      // Pre-installed small model, so the radio is selectable on open.
      await File('${tempDir.path}/qwen25-0-5b-it-q8.task')
          .writeAsBytes(Uint8List(2 * 1024 * 1024));
    });
    await open(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('On this phone'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final saved = await tester.runAsync(() => repo.load());
    expect(saved!.backend, AiBackend.onDevice);
    expect(saved.model, 'qwen-2.5-0.5b-it',
        reason: 'the chosen spec id rides the config model slot');
    await unmount(tester);
  });

  testWidgets('an interrupted download says Paused and offers Resume',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.runAsync(() async {
      await File('${tempDir.path}/qwen25-0-5b-it-q8.task.part')
          .writeAsBytes(Uint8List(1024 * 1024));
    });
    await open(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('On this phone'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(find.text('Resume'), findsOneWidget,
        reason: 'leaving the app pauses a download; the .part survives '
            'and Resume picks up from the same byte');
    expect(find.textContaining('Paused'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('delete asks first, then the model is gone', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.runAsync(() async {
      await File('${tempDir.path}/qwen25-0-5b-it-q8.task')
          .writeAsBytes(Uint8List(2 * 1024 * 1024));
    });
    await open(tester);
    await tester.tap(find.text('On this phone'));
    await tester.pumpAndSettle();
    // The section's initState fires its isDownloaded probes on this frame —
    // give the real file I/O a window, then repaint.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Downloaded'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete this model'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Delete'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Downloaded'), findsNothing);
    expect(find.text('Download'), findsNWidgets(2));
    await unmount(tester);
  });
}
