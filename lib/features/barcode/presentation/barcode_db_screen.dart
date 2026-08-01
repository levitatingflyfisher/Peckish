import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/features/barcode/data/barcode_db_download_service.dart';
import 'package:peckish/features/barcode/data/barcode_db_providers.dart';
import 'package:peckish/features/barcode/data/barcode_db_spec.dart';
import 'package:peckish/features/barcode/data/local_barcode_db.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/download_card.dart';

/// The offline barcode databases (ADR-0010): one card per catalog slice —
/// download (resumable, wakelock-held), delete. Statuses run on the
/// shared [DownloadCardEngine]'s sealed little state machine; a failed
/// download keeps its partial, so Resume picks up instead of restarting.
/// The footer says each database's license out loud, in plain text — the
/// ODbL attribution travels with the data it credits.
///
/// The route is reachable by direct URL on web too, where no slice can
/// ever install — that build gets a calm explanation instead of Download
/// buttons whose taps can only fail.
class BarcodeDbScreen extends ConsumerStatefulWidget {
  const BarcodeDbScreen({super.key, this.slicesSupportedOverride});

  /// Test seam only: production routes leave this null and the platform
  /// trio ([localSlicesSupported]) answers.
  final bool? slicesSupportedOverride;

  @override
  ConsumerState<BarcodeDbScreen> createState() => _BarcodeDbScreenState();
}

/// What an installed slice's own meta table reports.
typedef _SliceMeta = ({String? productCount, String? builtAt});

class _BarcodeDbScreenState extends ConsumerState<BarcodeDbScreen>
    with DownloadCardEngine<BarcodeDbScreen, BarcodeDbSpec, _SliceMeta> {
  bool get _slicesSupported =>
      widget.slicesSupportedOverride ?? localSlicesSupported;

  @override
  void initState() {
    super.initState();
    if (_slicesSupported) refreshDownloadStatuses();
  }

  @override
  Iterable<BarcodeDbSpec> get downloadItems => barcodeDbCatalog;

  @override
  String downloadIdOf(BarcodeDbSpec spec) => spec.id;

  @override
  Future<bool> isItemInstalled(BarcodeDbSpec spec) =>
      ref.read(barcodeDbDownloadServiceProvider).isInstalled(spec);

  @override
  Future<bool> itemHasPartial(BarcodeDbSpec spec) =>
      ref.read(barcodeDbDownloadServiceProvider).hasPartial(spec);

  @override
  Stream<(int, int)> itemDownloadStream(BarcodeDbSpec spec) =>
      ref.read(barcodeDbDownloadServiceProvider).download(spec);

  @override
  Future<void> deleteItemFiles(BarcodeDbSpec spec) =>
      ref.read(barcodeDbDownloadServiceProvider).delete(spec);

  @override
  String deleteConfirmTitle(BarcodeDbSpec spec) =>
      'Delete ${spec.displayName}?';

  @override
  String deleteConfirmMessage(BarcodeDbSpec spec) =>
      'Scans go back to asking — only when you say so. You can '
      'download it again any time.';

  /// Reads the slice's own meta table for provenance — product_count and
  /// built_at keep freshness visible (refresh is manual, twice a year).
  @override
  Future<DownloadInstalled<_SliceMeta>> installedStatusOf(
      BarcodeDbSpec spec) async {
    final path = await ref
        .read(barcodeDbDownloadServiceProvider)
        .installedDbPath(spec.id);
    if (path == null) return const DownloadInstalled();
    final db = LocalBarcodeDb(path);
    try {
      final meta = db.meta();
      return DownloadInstalled(
          (productCount: meta['product_count'], builtAt: meta['built_at']));
    } on Object {
      // A file that vanished mid-read still shows as installed-but-quiet;
      // the next visit re-checks.
      return const DownloadInstalled();
    } finally {
      db.close();
    }
  }

  /// Pick up product_count/built_at from the freshly installed file.
  @override
  Future<void> afterInstall(BarcodeDbSpec spec) => refreshDownloadStatuses();

  /// A checksum failure must read as what it is — not as a Wi-Fi drop.
  @override
  String? failureCopyOf(Object error) =>
      error is BarcodeDbIntegrityException ? error.message : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_slicesSupported) {
      return Scaffold(
        appBar: AppBar(title: const Text('Offline barcode lookup')),
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Offline barcode databases live on the phone app — on the web, '
            'lookups happen only when you ask.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Offline barcode lookup')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(
            'Download once, and barcode scans are answered on this phone — '
            'nothing leaves. A code these don\'t know can still be asked '
            'online, one tap at a time.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          for (final spec in barcodeDbCatalog)
            Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: DownloadCardTile<_SliceMeta>(
                status: downloadStatuses[spec.id] ?? const DownloadNotStarted(),
                title: spec.approxBytes > 0
                    ? '${spec.displayName} · '
                        '${formatApproxBytes(spec.approxBytes)}'
                    : spec.displayName,
                notDownloadedSubtitle: 'Not downloaded — scans ask online, '
                    'one tap at a time.',
                installedSubtitle: (theme, meta) => Text(
                    [
                      'On this phone',
                      if (meta?.productCount case final count?)
                        '$count products',
                      if (meta?.builtAt case final built?) 'built $built',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall),
                failedSubtitle: "Couldn't finish — trying again is safe.",
                deleteTooltip: 'Delete this database',
                onDownload: () => startDownload(spec),
                onDelete: () => confirmAndDeleteItem(spec),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          Text('About the data', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          for (final spec in barcodeDbCatalog)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '${spec.displayName}: ${spec.attribution} '
                '${spec.licenseName} — ${spec.licenseUrl}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          Text(
            'Databases are separate files and stay separate — Open Food '
            'Facts data remains under its own license.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
