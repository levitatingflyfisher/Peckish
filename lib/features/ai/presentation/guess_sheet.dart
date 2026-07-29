import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/ai/data/ai_config.dart';
import 'package:peckish/features/ai/data/ai_config_repository.dart';
import 'package:peckish/features/ai/data/guess_service.dart';
import 'package:peckish/features/ai/domain/meal_guess.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/features/ai/on_device/plate_lookup.dart';
import 'package:peckish/features/ai/on_device/plate_scan.dart';
import 'package:peckish/features/ai/on_device/plate_scanner.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:uuid/uuid.dart';

/// The platform key store; a single override point for tests.
final aiKeyStoreProvider = Provider<KeyStore>((_) => const SecureKeyStore());

final aiConfigRepositoryProvider = Provider<AiConfigRepository>((ref) =>
    AiConfigRepository(
        ref.watch(sharedPreferencesProvider), ref.watch(aiKeyStoreProvider)));

/// The current AI configuration. The add sheet gates its tile on
/// `configured`; invalidate after saving settings.
final aiConfigProvider = FutureProvider<AiConfig>(
    (ref) => ref.watch(aiConfigRepositoryProvider).load());

/// Test seam: a non-null client here replaces the wire.
final guessHttpClientProvider = Provider<http.Client?>((_) => null);

/// The guesstimate box: describe what you ate, the model drafts lines, you
/// prune and confirm. Nothing is logged until the confirm tap, and every
/// logged line carries `ai` provenance.
Future<void> showGuessSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _GuessSheet(),
    );

class _GuessSheet extends ConsumerStatefulWidget {
  const _GuessSheet();

  @override
  ConsumerState<_GuessSheet> createState() => _GuessSheetState();
}

class _GuessSheetState extends ConsumerState<_GuessSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _message;
  List<GuessedFood>? _draft;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Guess it for me', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _draft == null
                ? 'Describe the meal in your own words. The AI drafts the '
                    'lines; nothing is logged until you say so.'
                : 'AI guesses — prune what it got wrong, then log.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_draft == null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'e.g. chipotle bowl with double chicken',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                // The zero-download CV rung: classifier + bundled spine,
                // no AI configuration involved.
                if (plateScanSupported &&
                    ref.watch(plateScannerProvider) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: IconButton.filledTonal(
                      icon: const Icon(Icons.photo_camera_outlined),
                      tooltip: 'Snap your plate',
                      onPressed: _busy ? null : _snapPlate,
                    ),
                  ),
              ],
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(_message!, style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: _busy ? null : _guess,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Guess'),
            ),
          ] else ...[
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (i, food) in _draft!.indexed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(food.name),
                      subtitle: Text(_describe(food)),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Remove this line',
                        onPressed: () =>
                            setState(() => _draft!.removeAt(i)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(
              onPressed: _draft!.isEmpty ? null : () => _logAll(context),
              child: Text(
                  'Log ${_draft!.length} ${_draft!.length == 1 ? "entry" : "entries"}'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _draft = null;
                _message = null;
              }),
              child: const Text('Start over'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _guess() async {
    final description = _controller.text.trim();
    if (description.isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final config = await ref.read(aiConfigProvider.future);
      final service = GuessService(
        config: config,
        httpClient: ref.read(guessHttpClientProvider),
        localBrain: ref.read(localBrainProvider),
      );
      final guess = await service.guess(description);
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (guess.foods.isEmpty) {
          _message = "The AI couldn't make anything of that — try naming "
              'the foods more plainly, or Quick add them yourself.';
        } else {
          _draft = List.of(guess.foods);
        }
      });
    } on GuessException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e.message;
      });
    }
  }

  /// Snap your plate: photo → on-device classifier → bundled-spine drafts.
  /// Same confirm-before-commit flow as a text guess; a photo with nothing
  /// recognizable is a calm state with a next step, never an error.
  Future<void> _snapPlate() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final path = await ref.read(platePhotoPickerProvider)();
      if (path == null) {
        if (mounted) setState(() => _busy = false);
        return; // user backed out of the picker — nothing to say
      }
      final scanner = ref.read(plateScannerProvider)!;
      final labels = await scanner.labelsOf(path);
      final usda = ref.read(usdaFoodRepositoryProvider);
      final guess =
          await PlateScan.fromLabels(labels, (q) => plateLookup(usda, q));
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (guess.foods.isEmpty) {
          _message = "Couldn't spot any food in that photo — describe the "
              'meal below instead.';
        } else {
          _draft = List.of(guess.foods);
        }
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = "Couldn't read that photo — describe the meal below "
            'instead.';
      });
    }
  }

  Future<void> _logAll(BuildContext context) async {
    final now = DateTime.now();
    final diary = ref.read(diaryRepositoryProvider);
    for (final food in _draft!) {
      await diary.log(DiaryEntry(
        id: const Uuid().v4(),
        day: DiaryEntry.dayOf(now),
        at: now,
        food: const FoodRef.quick(),
        label: food.name,
        qty: food.grams ?? 1,
        unitLabel: food.grams != null ? 'g' : 'serving',
        grams: food.grams,
        macros: food.macros.clamped(),
        source: EntrySource.ai,
        createdAt: now,
      ));
    }
    if (context.mounted) Navigator.of(context).pop();
  }

  /// '~650 g · 905 kcal · estimate' — the confidence label in plain words.
  static String _describe(GuessedFood food) {
    final parts = <String>[
      if (food.grams != null) '~${food.grams!.round()} g',
      if (food.macros.kcal != null) '${food.macros.kcal!.round()} kcal',
      _confidenceLabel(food.confidence),
    ];
    return parts.join(' · ');
  }

  static String _confidenceLabel(double confidence) {
    if (confidence >= 0.7) return 'confident';
    if (confidence >= 0.4) return 'estimate';
    return 'wild guess';
  }
}
