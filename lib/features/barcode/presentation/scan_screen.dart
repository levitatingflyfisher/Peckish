import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peckish/features/barcode/data/off_client.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/presentation/barcode_sketch.dart';
import 'package:peckish/features/barcode/presentation/product_sheet.dart';
import 'package:peckish/features/barcode/presentation/scan_mode_store.dart';
import 'package:peckish/features/barcode/presentation/scanner_view.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// One lookup client for the app; overridable in tests.
final offClientProvider = Provider<OffClient>((ref) => OffClient());

/// Scan a barcode (camera, where there is one) or type the digits under the
/// bars (everywhere). Camera platforms get a Scan/Type toggle — Type it
/// unmounts the camera entirely — and the choice is remembered. One code =
/// one request to Open Food Facts = one confirm-before-commit sheet.
/// Failures are states with next steps, not errors.
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
      setState(() => _message =
          "That doesn't look like a barcode — check the numbers and try "
          'again.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final product =
          await ref.read(offClientProvider).fetchProduct(code);
      if (!mounted) return;
      // Latch held across the sheet's whole lifetime: the camera keeps
      // decoding underneath and must not stack a second sheet. Kept apart
      // from _busy so no spinner runs under the open sheet.
      setState(() {
        _busy = false;
        _sheetOpen = true;
      });
      final logged = await showProductSheet(context, product);
      if (!mounted) return;
      setState(() => _sheetOpen = false);
      // A log finishes the errand — back to where the user came from.
      if (logged == true) Navigator.of(context).pop();
    } on OffProductNotFound {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message =
            "This one's not in the shared database yet. Quick add it with "
            'the numbers from the label — takes ten seconds.';
      });
    } on OffLookupException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e.message;
      });
    }
  }
}
