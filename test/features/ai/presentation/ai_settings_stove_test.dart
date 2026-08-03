import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/ai_config_repository.dart';
import 'package:peckish/features/ai/data/stove_secret_store.dart';
import 'package:peckish/features/ai/presentation/ai_settings_dialog.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The stove tier in Settings, following the openai-compat entry pattern:
// pick 'Household stove', type where it lives and the household phrase,
// save. The phrase is validated with the same derivation the ask path uses
// — a typo is a calm line, never a crash, and never a mis-keyed save.
class _MemoryKeys implements KeyStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String? v) async => value = v;
}

void main() {
  const phrase = 'abandon abandon abandon abandon abandon abandon '
      'abandon abandon abandon abandon abandon about';

  late AiConfigRepository repo;
  late InMemoryStoveSecretStore stoveSecrets;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stoveSecrets = InMemoryStoveSecretStore();
    repo = AiConfigRepository(
        await SharedPreferences.getInstance(), _MemoryKeys(), stoveSecrets);
  });

  Widget host() => ProviderScope(
        overrides: [aiConfigRepositoryProvider.overrideWithValue(repo)],
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

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    await tester.tap(find.text('open ai settings'));
    await tester.pumpAndSettle();
  }

  Future<void> pickStove(WidgetTester tester) async {
    await tester.tap(find.text('Household stove'));
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Save'));
      // Phrase validation is real PBKDF2 work on another future.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('picking the stove reveals host, port, phrase and the promise',
      (tester) async {
    await open(tester);

    expect(find.text('Household stove'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Stove address'), findsNothing);

    await pickStove(tester);

    expect(find.widgetWithText(TextField, 'Stove address'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Port'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Household phrase'), findsOneWidget);
    expect(find.textContaining('the stove only ever learns its own key'),
        findsOneWidget,
        reason: 'the calm promise is the privacy contract');
  });

  testWidgets(
      'a valid save lands host + phrase; the port default is not '
      'stored', (tester) async {
    await open(tester);
    await pickStove(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Stove address'), '192.168.1.20');
    await tester.enterText(
        find.widgetWithText(TextField, 'Household phrase'), phrase);
    await save(tester);

    expect(find.text('Household stove'), findsNothing,
        reason: 'a clean save closes the dialog');
    final saved = await repo.load();
    expect(saved.backend, AiBackend.stove);
    expect(saved.stoveHost, '192.168.1.20');
    expect(saved.stovePort, isNull,
        reason: 'an untouched port rides the 4663 default at ask time');
    expect(saved.stovePhrase, phrase);
    expect(await stoveSecrets.read(), phrase,
        reason: 'the phrase belongs in secure storage');
  });

  testWidgets('an explicit port is kept', (tester) async {
    await open(tester);
    await pickStove(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Stove address'), 'stove.local');
    await tester.enterText(find.widgetWithText(TextField, 'Port'), '4700');
    await tester.enterText(
        find.widgetWithText(TextField, 'Household phrase'), phrase);
    await save(tester);

    expect((await repo.load()).stovePort, 4700);
  });

  testWidgets('an invalid phrase is a calm line and no save', (tester) async {
    await open(tester);
    await pickStove(tester);

    await tester.enterText(
        find.widgetWithText(TextField, 'Stove address'), 'stove.local');
    await tester.enterText(find.widgetWithText(TextField, 'Household phrase'),
        'definitely not twelve bip39 words');
    await save(tester);

    expect(find.text('Household stove'), findsOneWidget,
        reason: 'the dialog stays open to let the words be fixed');
    expect(find.textContaining("doesn't look like a household phrase"),
        findsOneWidget);
    final saved = await repo.load();
    expect(saved.backend, AiBackend.none,
        reason: 'nothing was saved under a mis-keyed phrase');
    expect(await stoveSecrets.read(), isNull);
  });

  testWidgets('an existing stove config comes back editable', (tester) async {
    await repo.save(const AiConfig(
      backend: AiBackend.stove,
      stoveHost: '10.0.0.7',
      stovePort: 4700,
      stovePhrase: phrase,
    ));
    await open(tester);

    expect(find.text('10.0.0.7'), findsOneWidget);
    expect(find.text('4700'), findsOneWidget);
    expect(find.text(phrase), findsOneWidget);
  });
}
