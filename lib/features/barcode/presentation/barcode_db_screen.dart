import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:peckish/features/barcode/data/barcode_db_providers.dart';
import 'package:peckish/features/barcode/data/barcode_db_spec.dart';
import 'package:peckish/features/barcode/data/local_barcode_db.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';

/// The offline barcode databases (ADR-0010): one card per catalog slice —
/// download (resumable, wakelock-held), delete. Statuses mirror the local
/// models section's sealed little state machine; a failed download keeps
/// its partial, so Resume picks up instead of restarting. The footer says
/// each database's license out loud, in plain text — the ODbL attribution
/// travels with the data it credits.
class BarcodeDbScreen extends ConsumerStatefulWidget {
  const BarcodeDbScreen({super.key});

  @override
  ConsumerState<BarcodeDbScreen> createState() => _BarcodeDbScreenState();
}

sealed class _Status {
  const _Status();
}

class _NotDownloaded extends _Status {
  const _NotDownloaded();
}

class _Paused extends _Status {
  const _Paused();
}

class _Downloading extends _Status {
  const _Downloading(this.percent);
  final int? percent; // null while the size is unknown
}

class _Installed extends _Status {
  const _Installed(this.productCount, this.builtAt);
  final String? productCount; // from the slice's own meta table
  final String? builtAt;
}

class _Failed extends _Status {
  const _Failed();
}

class _BarcodeDbScreenState extends ConsumerState<BarcodeDbScreen> {
  final _statuses = <String, _Status>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final service = ref.read(barcodeDbDownloadServiceProvider);
    for (final spec in barcodeDbCatalog) {
      final installed = await service.isInstalled(spec);
      final status = installed
          ? await _installedStatus(spec)
          : (await service.hasPartial(spec))
              ? const _Paused()
              : const _NotDownloaded();
      if (!mounted) return;
      setState(() => _statuses[spec.id] = status);
    }
  }

  /// Reads the slice's own meta table for provenance — product_count and
  /// built_at keep freshness visible (refresh is manual, twice a year).
  Future<_Status> _installedStatus(BarcodeDbSpec spec) async {
    final path = await ref
        .read(barcodeDbDownloadServiceProvider)
        .installedDbPath(spec.id);
    if (path == null) return const _Installed(null, null);
    final db = LocalBarcodeDb(path);
    try {
      final meta = db.meta();
      return _Installed(meta['product_count'], meta['built_at']);
    } on Object {
      // A file that vanished mid-read still shows as installed-but-quiet;
      // the next visit re-checks.
      return const _Installed(null, null);
    } finally {
      db.close();
    }
  }

  Future<void> _download(BarcodeDbSpec spec) async {
    setState(() => _statuses[spec.id] = const _Downloading(null));
    // Best-effort: a sleeping screen must not suspend the transfer, but a
    // platform without the plugin shouldn't break the download.
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    try {
      var lastPercent = -1;
      await for (final (received, total) in
          ref.read(barcodeDbDownloadServiceProvider).download(spec)) {
        if (!mounted) return;
        final percent = total <= 0 ? null : (received * 100 ~/ total);
        // Whole-percent throttle: a big file emits thousands of chunks.
        if (percent != lastPercent) {
          lastPercent = percent ?? -1;
          setState(() => _statuses[spec.id] = _Downloading(percent));
        }
      }
      if (!mounted) return;
      setState(() => _statuses[spec.id] = const _Installed(null, null));
      // Pick up product_count/built_at from the freshly installed file.
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      setState(() => _statuses[spec.id] = const _Failed());
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  Future<void> _delete(BarcodeDbSpec spec) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${spec.displayName}?',
      message: 'Scans go back to asking — only when you say so. You can '
          'download it again any time.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    await ref.read(barcodeDbDownloadServiceProvider).delete(spec);
    if (!mounted) return;
    setState(() => _statuses[spec.id] = const _NotDownloaded());
  }

  /// '430 MB' / '1.2 GB' — approximate by design, progress copy only.
  static String _size(int bytes) => bytes >= 1000 * 1000 * 1000
      ? '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(1)} GB'
      : '${bytes ~/ (1000 * 1000)} MB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              child: _card(
                  theme, spec, _statuses[spec.id] ?? const _NotDownloaded()),
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

  Widget _card(ThemeData theme, BarcodeDbSpec spec, _Status status) {
    return ListTile(
      title: Text(spec.approxBytes > 0
          ? '${spec.displayName} · ${_size(spec.approxBytes)}'
          : spec.displayName),
      subtitle: switch (status) {
        _NotDownloaded() => Text('Not downloaded — scans ask online, '
            'one tap at a time.',
            style: theme.textTheme.bodySmall),
        _Paused() => Text(
            'Paused partway — Resume picks up from the same byte.',
            style: theme.textTheme.bodySmall),
        _Downloading(:final percent) => Text(
            percent == null ? 'Downloading…' : 'Downloading… $percent%',
            style: theme.textTheme.bodySmall),
        _Installed(:final productCount, :final builtAt) => Text(
            [
              'On this phone',
              if (productCount != null) '$productCount products',
              if (builtAt != null) 'built $builtAt',
            ].join(' · '),
            style: theme.textTheme.bodySmall),
        _Failed() => Text(
            "Couldn't finish — trying again is safe.",
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.clay)),
      },
      trailing: switch (status) {
        _NotDownloaded() => TextButton(
            onPressed: () => _download(spec), child: const Text('Download')),
        _Paused() => TextButton(
            onPressed: () => _download(spec), child: const Text('Resume')),
        _Downloading() => const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
        _Installed() => IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete this database',
            onPressed: () => _delete(spec)),
        _Failed() => TextButton(
            onPressed: () => _download(spec), child: const Text('Retry')),
      },
    );
  }
}
