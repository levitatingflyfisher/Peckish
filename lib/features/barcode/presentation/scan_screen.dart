import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:peckish/features/barcode/data/barcode_resolver.dart';
import 'package:peckish/features/barcode/data/barcode_resolver_provider.dart';
import 'package:peckish/features/barcode/data/off_client.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/domain/off_product.dart';
import 'package:peckish/features/barcode/presentation/barcode_sketch.dart';
import 'package:peckish/features/barcode/presentation/product_sheet.dart';
import 'package:peckish/features/barcode/presentation/scan_mode_store.dart';
import 'package:peckish/features/barcode/presentation/scanner_view.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// One lookup client for the app; overridable in tests.
final offClientProvider = Provider<OffClient>((ref) => OffClient());

/// Scan a barcode (camera, where there is one) or type the digits under the
/// bars (everywhere). Camera platforms get a Scan/Type toggle — Type it
/// unmounts the camera entirely — and the choice is remembered.
///
/// ADR-0010's law: the phone answers first. A code resolves against the
/// downloaded slices; a local hit opens the confirm sheet with zero
/// network. A miss is a STATE offering an explicit "Ask openfoodfacts.org"
/// button — no code path in this screen reaches the network without that
/// tap. Failures are states with next steps, not errors.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.debugCameraOverride});

  /// Tests force the camera layout on the camera-less VM; real builds
  /// leave this null and follow [ScannerView.available].
  @visibleForTesting
  final bool? debugCameraOverride;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = TextEditingController();
  bool _busy = false; // lookup in flight → spinner + disabled field
  bool _sheetOpen = false; // confirm sheet up → repeat scans are swallowed
  String? _message;

  /// The code the local slices didn't know, held so the Ask button can
  /// forward it unchanged. Non-null = the miss state is showing.
  BarcodeCode? _missCode;

  /// Whether any slice was actually consulted for [_missCode] — false
  /// truthfully points the miss at the offline download instead.
  bool _missAnyLocalDb = false;

  /// Null while the remembered choice loads (camera platforms): the camera
  /// must not warm up in that gap for a user who chose typing.
  ScanMode? _mode;

  /// A tap in the load gap wins over the arriving remembered value.
  bool _userChose = false;

  bool get _hasCamera => widget.debugCameraOverride ?? ScannerView.available;

  @override
  void initState() {
    super.initState();
    if (_hasCamera) {
      unawaited(_restoreMode());
    } else {
      _mode = ScanMode.type;
    }
  }

  Future<void> _restoreMode() async {
    final saved = await ref.read(scanModeStoreProvider).load();
    if (!mounted || _userChose) return;
    setState(() => _mode = saved ?? ScanMode.camera);
  }

  void _setMode(ScanMode mode) {
    _userChose = true;
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _message = null;
      _missCode = null;
    });
    unawaited(ref.read(scanModeStoreProvider).save(mode));
  }

  /// Camera couldn't start (permission, hardware): land on typing with one
  /// calm line. Deliberately not persisted — a transient failure shouldn't
  /// overwrite the user's choice.
  void _onCameraError(Exception _) {
    if (!mounted) return;
    setState(() {
      _mode = ScanMode.type;
      _message = "The camera couldn't start here — type the numbers instead.";
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a barcode')),
      body: Column(
        children: [
          if (_hasCamera)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: SegmentedButton<ScanMode>(
                segments: const [
                  ButtonSegment(
                      value: ScanMode.camera,
                      label: Text('Scan'),
                      icon: Icon(Icons.photo_camera_outlined)),
                  ButtonSegment(
                      value: ScanMode.type,
                      label: Text('Type it'),
                      icon: Icon(Icons.keyboard_outlined)),
                ],
                selected: {if (_mode != null) _mode!},
                emptySelectionAllowed: true,
                onSelectionChanged: (s) => _setMode(s.first),
              ),
            ),
          Expanded(
            child: switch (_mode) {
              ScanMode.camera => _cameraPane(theme),
              ScanMode.type => _typePane(),
              // The one frame before the remembered choice arrives.
              null => const SizedBox.shrink(),
            },
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(_message!,
                          style: theme.textTheme.bodyMedium),
                    ),
                  // The miss state: the network is a question, asked out
                  // loud. Nothing fetches until this button is tapped.
                  if (_missCode != null) ...[
                    OutlinedButton(
                      onPressed: _busy ? null : _askOnline,
                      child: const Text('Ask openfoodfacts.org'),
                    ),
                    // Web has no local slices (ADR-0010): no pointer there.
                    if (!_missAnyLocalDb && !kIsWeb)
                      TextButton(
                        onPressed: () => context.push('/barcode-db'),
                        child: const Text('Get the offline database'),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  TextField(
                    controller: _controller,
                    enabled: !_busy && !_sheetOpen,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Barcode numbers',
                      hintText: 'e.g. 3017620422003',
                      border: const OutlineInputBorder(),
                      suffixIcon: _busy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () =>
                                  _handleRaw(_controller.text),
                            ),
                    ),
                    onSubmitted: _handleRaw,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cameraPane(ThemeData theme) => Column(
        children: [
          Expanded(
            child: ScannerView(onCode: _handleRaw, onError: _onCameraError),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: Text(
              // The v0.2 lesson: with no shutter button, people wait for
              // one. Say out loud that none is needed.
              'Hold the barcode in view — it reads on its own. '
              'Dim light? Try the flash.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      );

  Widget _typePane() => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: BarcodeSketch(),
        ),
      );

  Future<void> _handleRaw(String raw) async {
    // The camera can fire the same code many times — during a lookup AND
    // under an open sheet.
    if (_busy || _sheetOpen) return;
    final code = BarcodeCode.tryParse(raw);
    if (code == null) {
      setState(() {
        // The pending Ask dies with the old code: a live button aimed at
        // the PREVIOUS scan would log the wrong food two taps later.
        _missCode = null;
        _message =
            "That doesn't look like a barcode — check the numbers and try "
            'again.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
      _missCode = null;
    });
    // The phone answers first — and only the phone. The one network path
    // in this screen is _askOnline, behind its explicit tap.
    final BarcodeResolution resolution;
    try {
      resolution = await ref.read(barcodeResolverProvider).resolveLocal(code);
    } on Object {
      // resolveLocal is documented never to throw — but if that promise
      // ever breaks, the screen's own contract (failures are states, never
      // a stuck spinner) must survive it.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = "Couldn't check your phone's database — try again.";
      });
      return;
    }
    if (!mounted) return;
    switch (resolution) {
      case BarcodeHit(:final product, :final sourceId):
        await _openSheet(product, sourceNote: _sourceNote(sourceId));
      case BarcodeMiss(:final anyLocalDb):
        setState(() {
          _busy = false;
          _missCode = code;
          _missAnyLocalDb = anyLocalDb;
          _message = anyLocalDb
              ? "Not in your phone's food database."
              : kIsWeb
                  // Web has no local slices (ADR-0010): don't promise one.
                  ? 'Not looked up yet — on the web, lookups only happen '
                      'when you ask.'
                  : "Peckish hasn't looked this up — barcode answers can "
                      'live on your phone.';
        });
    }
  }

  /// The one sanctioned network path: the user tapped Ask, so this code —
  /// the 13 digits, nothing else — goes to Open Food Facts once.
  Future<void> _askOnline() async {
    final code = _missCode;
    if (code == null || _busy || _sheetOpen) return;
    setState(() => _busy = true);
    try {
      final product = await ref.read(offClientProvider).fetchProduct(code);
      if (!mounted) return;
      await _openSheet(product, sourceNote: 'From openfoodfacts.org');
    } on OffProductNotFound {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _missCode = null;
        _message =
            "This one's not in the shared database yet. Quick add it with "
            'the numbers from the label — takes ten seconds.';
      });
    } on OffLookupException catch (e) {
      if (!mounted) return;
      // The miss state stays up: a flaky connection deserves a second tap
      // without rescanning.
      setState(() {
        _busy = false;
        _message = e.message;
      });
    } on Object {
      // An Error (not Exception) escaping the client — a transport bug, a
      // malformed answer — must not latch _busy and brick the screen.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = "That didn't work — try again in a moment.";
      });
    }
  }

  Future<void> _openSheet(OffProduct product, {String? sourceNote}) async {
    // Latch held across the sheet's whole lifetime: the camera keeps
    // decoding underneath and must not stack a second sheet. Kept apart
    // from _busy so no spinner runs under the open sheet.
    setState(() {
      _busy = false;
      _sheetOpen = true;
      _missCode = null;
      _message = null;
    });
    final logged =
        await showProductSheet(context, product, sourceNote: sourceNote);
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    // A log finishes the errand — back to where the user came from.
    if (logged == true) Navigator.of(context).pop();
  }

  /// Credits the slice that answered — ODbL wants attribution pinned to
  /// the OFF data (ADR-0010).
  static String _sourceNote(String sourceId) => switch (sourceId) {
        'usda' => 'From your phone — USDA database',
        'off_us' => 'From your phone — Open Food Facts',
        _ => 'From your phone',
      };
}
