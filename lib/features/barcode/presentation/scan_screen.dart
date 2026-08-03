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
import 'package:peckish/features/barcode/presentation/scanner_view.dart';
import 'package:peckish/features/diary/presentation/regulars_rail.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// One lookup client for the app; overridable in tests.
final offClientProvider = Provider<OffClient>((ref) => OffClient());

/// Scan a barcode (camera, where there is one) or type the digits under the
/// bars — one screen, not two modes. The digits field is live in every
/// state, so there is nothing to choose between and nothing to remember:
/// the camera is simply UP when there is nothing to deal with, and DOWN the
/// moment there is (a lookup in flight, a question awaiting your answer,
/// the confirm sheet open). One button parks it for this visit.
///
/// v0.6 shipped a remembered Scan/Type toggle. Two v0.8 phone findings
/// retired it: remembering could only ever cost a click (camera-up already
/// serves the typist), and a preview left running under a decoded code —
/// most visibly after picking a photo from the gallery — is a camera doing
/// nothing but drawing power.
///
/// ADR-0010's law: the phone answers first. A code resolves against your
/// own saved foods and then the downloaded slices; a local hit needs zero
/// network. A miss is a STATE offering an explicit "Ask openfoodfacts.org"
/// button — no code path in this screen reaches the network without that
/// tap. Failures are states with next steps, not errors.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({
    super.key,
    this.debugCameraOverride,
    this.day,
    this.startTyping = false,
  });

  /// Tests force the camera layout on the camera-less VM; real builds
  /// leave this null and follow [ScannerView.available].
  @visibleForTesting
  final bool? debugCameraOverride;

  /// The past day this scan feeds (null = today) — carried straight through
  /// to the confirm sheet, which is the only thing that writes.
  final String? day;

  /// Opened through the "Type a barcode" door: the camera starts parked and
  /// the digits field has the cursor.
  ///
  /// This is a starting posture, not a mode — nothing is remembered, and
  /// the camera is one tap away exactly as it is on any other visit. It
  /// exists because the merged screen gave the typist one door and it was
  /// the camera's.
  final bool startTyping;

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

  /// The code most recently read, shown in place of the preview while it is
  /// being dealt with — a picked gallery photo especially, where there is
  /// otherwise nothing on screen saying what was decoded.
  BarcodeCode? _read;

  /// Parked by hand for this visit, by the "Type a barcode" door, or by a
  /// camera that couldn't start. Deliberately not persisted: see the class
  /// comment.
  late bool _cameraOff = widget.startTyping;

  bool get _hasCamera => widget.debugCameraOverride ?? ScannerView.available;

  /// Something is in hand — a lookup running, a question waiting, a sheet
  /// open. Nothing is being scanned, so nothing should be scanning.
  bool get _busyWithACode => _busy || _sheetOpen || _missCode != null;

  bool get _cameraUp => _hasCamera && !_cameraOff && !_busyWithACode;

  /// Camera couldn't start (permission, hardware): park it with one calm
  /// line. The digits field was already there, so there is nothing to fall
  /// back TO — it just stops promising a preview it cannot give.
  void _onCameraError(Exception _) {
    if (!mounted) return;
    setState(() {
      _cameraOff = true;
      _message = "The camera couldn't start here — type the numbers instead.";
    });
  }

  /// Drop a dealt-with code and go back to hunting. The stale question dies
  /// with it: a live Ask button aimed at the PREVIOUS scan would log the
  /// wrong food two taps later.
  void _scanAgain() => setState(() {
        _missCode = null;
        _read = null;
        _message = null;
      });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a barcode'),
        actions: [
          if (_hasCamera)
            IconButton(
              icon: Icon(_cameraOff
                  ? Icons.videocam_off_outlined
                  : Icons.videocam_outlined),
              tooltip:
                  _cameraOff ? 'Turn the camera on' : 'Turn the camera off',
              onPressed: () => setState(() => _cameraOff = !_cameraOff),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _cameraUp
                ? _cameraPane(theme)
                : _busyWithACode && _read != null
                    ? _readPane(theme, _read!)
                    : _typePane(),
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
                      child: Text(_message!, style: theme.textTheme.bodyMedium),
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
                    // The way out of the question, and back to hunting.
                    TextButton(
                      onPressed: _busy ? null : _scanAgain,
                      child: const Text('Scan again'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  TextField(
                    controller: _controller,
                    // Only through the Type door. Everywhere else the
                    // camera is the point, and a keyboard over the preview
                    // is the thing being fixed, not the fix.
                    autofocus: widget.startTyping,
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () => _handleRaw(_controller.text),
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

  /// What replaces the preview once a code is in hand: the digits that were
  /// actually read. A photo picked from the gallery decodes with nothing on
  /// screen to show for it, and a live preview there is worse than nothing
  /// — it says "still scanning" while the app has already stopped.
  Widget _readPane(ThemeData theme, BarcodeCode code) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.qr_code_2, size: 44),
              const SizedBox(height: AppSpacing.sm),
              Text('Read ${code.value}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium),
            ],
          ),
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
      _read = code;
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
      // Your own shelf: you already decided what this is and how much of
      // it you eat, so there is nothing left to confirm. "Save to My Foods"
      // promises the next scan is one tap — this is that tap.
      case BarcodeSavedFood(:final food):
        setState(() => _busy = false);
        await logRegular(context, ref, food.asTemplateEntry(), day: widget.day);
        if (mounted) Navigator.of(context).pop();
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
    final logged = await showProductSheet(context, product,
        sourceNote: sourceNote, day: widget.day);
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
