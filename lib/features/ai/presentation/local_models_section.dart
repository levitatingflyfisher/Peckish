import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/features/ai/on_device/model_spec.dart';
import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/download_card.dart';

/// The small model manager inside the AI dialog: one card per catalog
/// entry — download (resumable, wakelock-held), pick, delete. Statuses
/// run on the shared [DownloadCardEngine]'s sealed little state machine
/// per model; a failed download keeps its .part, so Retry resumes
/// instead of restarting.
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

class _LocalModelsSectionState extends ConsumerState<LocalModelsSection>
    with DownloadCardEngine<LocalModelsSection, PeckishModelSpec, Never> {
  @override
  void initState() {
    super.initState();
    refreshDownloadStatuses();
  }

  @override
  Iterable<PeckishModelSpec> get downloadItems =>
      PeckishModelSpec.availableModels;

  @override
  String downloadIdOf(PeckishModelSpec spec) => spec.id;

  @override
  Future<bool> isItemInstalled(PeckishModelSpec spec) =>
      ref.read(modelDownloadServiceProvider).isDownloaded(spec);

  @override
  Future<bool> itemHasPartial(PeckishModelSpec spec) =>
      ref.read(modelDownloadServiceProvider).hasPartial(spec);

  @override
  Stream<(int, int)> itemDownloadStream(PeckishModelSpec spec) =>
      ref.read(modelDownloadServiceProvider).download(spec);

  @override
  Future<void> deleteItemFiles(PeckishModelSpec spec) =>
      ref.read(modelDownloadServiceProvider).delete(spec);

  @override
  String deleteConfirmTitle(PeckishModelSpec spec) =>
      'Delete ${spec.displayName}?';

  @override
  String deleteConfirmMessage(PeckishModelSpec spec) =>
      'Frees ${formatApproxBytes(spec.sizeBytes)}. You can download it '
      'again any time.';

  @override
  Widget build(BuildContext context) {
    // Its OWN radio group: nesting bare radios inside the dialog's
    // backend RadioGroup makes semantics see two checked children in one
    // group. A tap on a not-yet-downloaded model is simply ignored.
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.md),
      child: RadioGroup<String>(
        groupValue: widget.selectedId,
        onChanged: (id) {
          if (id != null && downloadStatuses[id] is DownloadInstalled) {
            widget.onSelect(id);
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final spec in PeckishModelSpec.availableModels)
              DownloadCardTile<Never>(
                status:
                    downloadStatuses[spec.id] ?? const DownloadNotStarted(),
                title: '${spec.displayName} · '
                    '${formatApproxBytes(spec.sizeBytes)}',
                leading: Radio<String>(value: spec.id),
                contentPadding: EdgeInsets.zero,
                notDownloadedSubtitle: spec.description,
                installedSubtitle: (theme, detail) =>
                    const Text('Downloaded'),
                failedSubtitle:
                    "Couldn't finish — Retry picks up where it stopped.",
                deleteTooltip: 'Delete this model',
                onDownload: () => startDownload(spec),
                onDelete: () => confirmAndDeleteItem(spec),
              ),
          ],
        ),
      ),
    );
  }
}
