import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';

/// The one download-card engine behind both download UIs (the AI dialog's
/// local models, the barcode screen's offline slices): the sealed
/// per-item status machine, the download driver, delete-with-confirm,
/// and the [DownloadCardTile] that renders a card. Copy that differs
/// between the two screens differs on purpose and arrives as parameters.

/// The sealed little state machine every download card runs on; a failed
/// download keeps its partial, so Resume/Retry picks up instead of
/// restarting. [D] is whatever detail an installed item carries (the
/// barcode slice's meta-table facts; nothing for a model).
sealed class DownloadStatus<D> {
  const DownloadStatus();
}

final class DownloadNotStarted<D> extends DownloadStatus<D> {
  const DownloadNotStarted();
}

final class DownloadPaused<D> extends DownloadStatus<D> {
  const DownloadPaused();
}

final class DownloadInProgress<D> extends DownloadStatus<D> {
  const DownloadInProgress(this.percent);
  final int? percent; // null while the size is unknown
}

final class DownloadInstalled<D> extends DownloadStatus<D> {
  const DownloadInstalled([this.detail]);
  final D? detail;
}

final class DownloadFailed<D> extends DownloadStatus<D> {
  const DownloadFailed([this.message]);

  /// A failure that knows its own story (the barcode slice's checksum
  /// mismatch) carries it here; null falls back to the card's generic
  /// failed copy — a checksum failure should never read as a Wi-Fi drop.
  final String? message;
}

/// '430 MB' / '1.2 GB' — approximate by design, progress copy only.
String formatApproxBytes(int bytes) => bytes >= 1000 * 1000 * 1000
    ? '${(bytes / (1000 * 1000 * 1000)).toStringAsFixed(1)} GB'
    : '${bytes ~/ (1000 * 1000)} MB';

/// Decides which progress chunks earn a setState. A known total emits on
/// whole-percent change; an unknown one (no Content-Length) emits on the
/// first chunk and then every ~512 KB — never per chunk. The old
/// `percent != lastPercent` check compared null against -1 and passed
/// EVERY chunk of an unknown-length transfer: a setState storm feeding a
/// bar that shows no percent at all.
class DownloadProgressThrottle {
  /// Unknown-total transfers redraw this often, by received bytes.
  static const int unknownTotalStepBytes = 512 * 1024;

  int _lastPercent = -1;
  int _lastEmittedBytes = -1;

  /// True when this `(received, total)` chunk should reach the UI.
  bool shouldEmit(int received, int total) {
    if (total > 0) {
      final percent = received * 100 ~/ total;
      if (percent == _lastPercent) return false;
      _lastPercent = percent;
      _lastEmittedBytes = received;
      return true;
    }
    if (_lastEmittedBytes >= 0 &&
        received - _lastEmittedBytes < unknownTotalStepBytes) {
      return false;
    }
    _lastEmittedBytes = received;
    return true;
  }
}

/// The one screen-awake lamp shared by every concurrent download. Two
/// transfers can overlap (two slices, or a model plus a slice); without a
/// refcount the first finisher's `finally` switched the wakelock off under
/// the survivor. Enable fires on 0→1, disable on 1→0, and each platform
/// call is best-effort — a platform without the plugin must never break a
/// download.
class WakelockRefcount {
  WakelockRefcount({
    Future<void> Function()? enable,
    Future<void> Function()? disable,
  })  : _enable = enable ?? WakelockPlus.enable,
        _disable = disable ?? WakelockPlus.disable;

  final Future<void> Function() _enable;
  final Future<void> Function() _disable;
  int _holders = 0;

  Future<void> acquire() async {
    _holders++;
    if (_holders == 1) {
      try {
        await _enable();
      } catch (_) {}
    }
  }

  Future<void> release() async {
    // A stray extra release must not push the count negative and eat the
    // next holder's enable.
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) {
      try {
        await _disable();
      } catch (_) {}
    }
  }
}

/// The app-wide instance every [DownloadCardEngine] download holds.
final WakelockRefcount downloadWakelock = WakelockRefcount();

/// The controller half of a download UI: one [DownloadStatus] per item
/// id, refreshed from disk, driven through download (resumable,
/// wakelock-held) and delete-with-confirm. The host State wires its own
/// service calls and copy through the abstract members.
mixin DownloadCardEngine<W extends StatefulWidget, S, D> on State<W> {
  /// Status per item id; an item never probed renders as not started.
  final downloadStatuses = <String, DownloadStatus<D>>{};

  // ---- what the host wires ---------------------------------------------

  /// The catalog this engine manages, one card each.
  Iterable<S> get downloadItems;

  String downloadIdOf(S item);
  Future<bool> isItemInstalled(S item);
  Future<bool> itemHasPartial(S item);
  Stream<(int, int)> itemDownloadStream(S item);
  Future<void> deleteItemFiles(S item);
  String deleteConfirmTitle(S item);
  String deleteConfirmMessage(S item);

  /// The status an installed item shows. Override to attach a probed
  /// [DownloadInstalled.detail] (the barcode screen reads the slice's
  /// own meta table here).
  Future<DownloadInstalled<D>> installedStatusOf(S item) async =>
      DownloadInstalled<D>();

  /// Runs after a download lands, still inside the try — a throw here is
  /// a Failed card. Override to re-probe what only the installed file
  /// can answer.
  Future<void> afterInstall(S item) async {}

  /// Copy for a failure the host can name (the barcode screen maps its
  /// integrity exception's own message). Null — the default — falls back
  /// to the card's generic failed subtitle.
  String? failureCopyOf(Object error) => null;

  // ---- the engine ------------------------------------------------------

  Future<void> refreshDownloadStatuses() async {
    for (final item in downloadItems) {
      final id = downloadIdOf(item);
      // A live download owns its card: a sibling's completion refresh
      // flipping it back to Paused would offer Resume — a second writer on
      // the same partial.
      if (downloadStatuses[id] is DownloadInProgress<D>) continue;
      try {
        final installed = await isItemInstalled(item);
        final status = installed
            ? await installedStatusOf(item)
            : (await itemHasPartial(item))
                ? DownloadPaused<D>()
                : DownloadNotStarted<D>();
        if (!mounted) return;
        // The probes awaited; a download may have started meanwhile.
        if (downloadStatuses[id] is DownloadInProgress<D>) continue;
        setState(() => downloadStatuses[id] = status);
      } catch (_) {
        // One item's disk hiccup must not abort the sweep — the loop is
        // fired from initState, where an escaped throw has no catcher.
        continue;
      }
    }
  }

  Future<void> startDownload(S item) async {
    final id = downloadIdOf(item);
    setState(() => downloadStatuses[id] = DownloadInProgress<D>(null));
    // A sleeping screen must not suspend the transfer; the refcount keeps
    // the lamp lit until the LAST concurrent download finishes.
    await downloadWakelock.acquire();
    try {
      final throttle = DownloadProgressThrottle();
      await for (final (received, total) in itemDownloadStream(item)) {
        if (!mounted) return;
        final percent = total <= 0 ? null : (received * 100 ~/ total);
        if (throttle.shouldEmit(received, total)) {
          setState(() => downloadStatuses[id] = DownloadInProgress<D>(percent));
        }
      }
      if (!mounted) return;
      setState(() => downloadStatuses[id] = DownloadInstalled<D>());
      await afterInstall(item);
    } catch (e) {
      if (!mounted) return;
      setState(
          () => downloadStatuses[id] = DownloadFailed<D>(failureCopyOf(e)));
    } finally {
      await downloadWakelock.release();
    }
  }

  Future<void> confirmAndDeleteItem(S item) async {
    final confirmed = await showConfirmDialog(
      context,
      title: deleteConfirmTitle(item),
      message: deleteConfirmMessage(item),
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    await deleteItemFiles(item);
    if (!mounted) return;
    setState(
        () => downloadStatuses[downloadIdOf(item)] = DownloadNotStarted<D>());
  }
}

/// The rendering half: one card as a ListTile whose subtitle and trailing
/// action follow the status. Wording the two screens genuinely share
/// (Paused / Downloading / the action verbs) lives here; everything that
/// differs — including the copy — is a parameter or a slot.
class DownloadCardTile<D> extends StatelessWidget {
  const DownloadCardTile({
    super.key,
    required this.status,
    required this.title,
    this.leading,
    this.contentPadding,
    required this.notDownloadedSubtitle,
    required this.installedSubtitle,
    required this.failedSubtitle,
    required this.deleteTooltip,
    required this.onDownload,
    required this.onDelete,
  });

  final DownloadStatus<D> status;
  final String title;

  /// Extras slot: the model card's leading radio.
  final Widget? leading;
  final EdgeInsetsGeometry? contentPadding;
  final String notDownloadedSubtitle;

  /// Extras slot: what an installed card says (the barcode card's
  /// product-count/built-at footer; the model card's plain 'Downloaded').
  final Widget Function(ThemeData theme, D? detail) installedSubtitle;
  final String failedSubtitle;
  final String deleteTooltip;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: contentPadding,
      leading: leading,
      title: Text(title),
      subtitle: switch (status) {
        DownloadNotStarted() =>
          Text(notDownloadedSubtitle, style: theme.textTheme.bodySmall),
        DownloadPaused() => Text(
            'Paused partway — Resume picks up from the same byte.',
            style: theme.textTheme.bodySmall),
        DownloadInProgress(:final percent) => Text(
            percent == null ? 'Downloading…' : 'Downloading… $percent%',
            style: theme.textTheme.bodySmall),
        DownloadInstalled(:final detail) => installedSubtitle(theme, detail),
        // A failure that names itself outranks the generic line.
        DownloadFailed(:final message) => Text(message ?? failedSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: AppColors.clay)),
      },
      trailing: switch (status) {
        DownloadNotStarted() =>
          TextButton(onPressed: onDownload, child: const Text('Download')),
        DownloadPaused() =>
          TextButton(onPressed: onDownload, child: const Text('Resume')),
        DownloadInProgress() => const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2)),
        DownloadInstalled() => IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: deleteTooltip,
            onPressed: onDelete),
        DownloadFailed() =>
          TextButton(onPressed: onDownload, child: const Text('Retry')),
      },
    );
  }
}
