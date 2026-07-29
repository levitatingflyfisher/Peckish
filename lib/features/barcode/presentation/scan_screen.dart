import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peckish/features/barcode/data/off_client.dart';
import 'package:peckish/features/barcode/domain/barcode_code.dart';
import 'package:peckish/features/barcode/presentation/product_sheet.dart';
import 'package:peckish/features/barcode/presentation/scanner_view.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// One lookup client for the app; overridable in tests.
final offClientProvider = Provider<OffClient>((ref) => OffClient());

/// Scan a barcode (camera, where there is one) or type the digits under the
/// bars (everywhere). One code = one request to Open Food Facts = one
/// confirm-before-commit sheet. Failures are states with next steps, not
/// errors.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = TextEditingController();
  bool _busy = false; // lookup in flight → spinner + disabled field
  bool _sheetOpen = false; // confirm sheet up → repeat scans are swallowed
  String? _message;

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
          if (ScannerView.available)
            Expanded(child: ScannerView(onCode: _handleRaw))
          else
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner,
                          size: 64,
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.4)),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'No camera scanning here — type the numbers '
                        'printed under the bars instead.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
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
      await showProductSheet(context, product);
      if (!mounted) return;
      setState(() => _sheetOpen = false);
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
