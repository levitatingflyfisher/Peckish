import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:peckish/features/ai/on_device/model_spec.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';

/// The small model manager inside the AI dialog: one card per catalog
/// entry — download (resumable, wakelock-held), pick, delete. Statuses are
/// a sealed little state machine per model; a failed download keeps its
/// .part, so Retry resumes instead of restarting.
class LocalModelsSection extends ConsumerStatefulWidget {
  const LocalModelsSection({
    super.key,
    required this.selectedId,
    required this.onSelect,
  });

  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  ConsumerState<LocalModelsSection> createState() =>
      _LocalModelsSectionState();
}

sealed class _Status {
  const _Status();
}

class _NotDownloaded extends _Status {
  const _NotDownloaded();
}

class _Downloading extends _Status {
  const _Downloading(this.percent);
  final int? percent; // null while the size is unknown
}

class _Installed extends _Status {
  const _Installed();
}

class _Failed extends _Status {
  const _Failed();
}

class _LocalModelsSectionState extends ConsumerState<LocalModelsSection> {
  final _statuses = <String, _Status>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final downloads = ref.read(modelDownloadServiceProvider);
    for (final spec in PeckishModelSpec.availableModels) {
      final installed = await downloads.isDownloaded(spec);
      if (!mounted) return;
      setState(() => _statuses[spec.id] =
          installed ? const _Installed() : const _NotDownloaded());
    }
  }

  Future<void> _download(PeckishModelSpec spec) async {
    setState(() => _statuses[spec.id] = const _Downloading(null));
    // Best-effort: a sleeping screen must not suspend a half-GB transfer,
    // but a platform without the plugin shouldn't break the download.
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    try {
      var lastPercent = -1;
      await for (final (received, total) in
          ref.read(modelDownloadServiceProvider).download(spec)) {
        if (!mounted) return;
        final percent = total <= 0 ? null : (received * 100 ~/ total);
        // Whole-percent throttle: a GB file emits thousands of chunks.
        if (percent != lastPercent) {
          lastPercent = percent ?? -1;
          setState(() => _statuses[spec.id] = _Downloading(percent));
        }
      }
      if (!mounted) return;
      setState(() => _statuses[spec.id] = const _Installed());
    } catch (_) {
      if (!mounted) return;
      setState(() => _statuses[spec.id] = const _Failed());
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
    }
  }

  Future<void> _delete(PeckishModelSpec spec) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${spec.displayName}?',
      message: 'Frees ${_gb(spec.sizeBytes)}. You can download it again '
          'any time.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    await ref.read(modelDownloadServiceProvider).delete(spec);
    if (!mounted) return;
    setState(() => _statuses[spec.id] = const _NotDownloaded());
  }

  static String _gb(int bytes) => bytes >= 1000 * 1000 * 1000
      ? '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(1)} GB'
      : '${bytes ~/ (1000 * 1000)} MB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Its OWN radio group: nesting bare radios inside the dialog's
    // backend RadioGroup makes semantics see two checked children in one
    // group. A tap on a not-yet-downloaded model is simply ignored.
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: RadioGroup<String>(
        groupValue: widget.selectedId,
        onChanged: (id) {
          if (id != null && _statuses[id] is _Installed) {
            widget.onSelect(id);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final spec in PeckishModelSpec.availableModels)
              _card(
                  theme, spec, _statuses[spec.id] ?? const _NotDownloaded()),
          ],
        ),
      ),
    );
  }

  Widget _card(ThemeData theme, PeckishModelSpec spec, _Status status) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Radio<String>(value: spec.id),
      title: Text('${spec.displayName} · ${_gb(spec.sizeBytes)}'),
      subtitle: switch (status) {
        _NotDownloaded() =>
          Text(spec.description, style: theme.textTheme.bodySmall),
        _Downloading(:final percent) => Text(
            percent == null ? 'Downloading…' : 'Downloading… $percent%',
            style: theme.textTheme.bodySmall),
        _Installed() => const Text('Downloaded'),
        _Failed() => Text(
            "Couldn't finish — Retry picks up where it stopped.",
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.clay)),
      },
      trailing: switch (status) {
        _NotDownloaded() => TextButton(
            onPressed: () => _download(spec), child: const Text('Download')),
        _Downloading() => const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
        _Installed() => IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete this model',
            onPressed: () => _delete(spec)),
        _Failed() => TextButton(
            onPressed: () => _download(spec), child: const Text('Retry')),
      },
    );
  }
}
