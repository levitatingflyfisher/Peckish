import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:peckish/features/ai/on_device/on_device_providers.dart';
import 'package:peckish/features/ai/on_device/plate_scanner.dart';
import 'package:peckish/features/ai/presentation/guess_sheet.dart';
import 'package:peckish/features/diary/presentation/add_sheet.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// The bottom-right + as a speed-dial, replacing the plain FAB on Today and
/// any past day. Root cause #3: the ways to add food used to live at the
/// TOP of the + sheet — the far end of a one-handed reach. Every route now
/// extends upward from the thumb, nearest-first by frequency: **Find
/// food** (the sheet, day-aware — search + regulars + saved meals),
/// **Quick add**, **Scan**, **Type a code**, and **Guess it** once a brain
/// is ready (the same gate `add_sheet.dart` used to hold).
///
/// This also RESOLVES the v0.3/#184 compromise (routes stacked above the
/// regulars list, pushing them off the first screenful) rather than
/// fighting it: with the routes on the dial, the sheet becomes pure
/// find-and-relog.
class SpeedDialFab extends ConsumerStatefulWidget {
  const SpeedDialFab({super.key, this.day});

  /// Null = today; otherwise the past day every route feeds.
  final String? day;

  @override
  ConsumerState<SpeedDialFab> createState() => _SpeedDialFabState();
}

/// Where the "Type a barcode" door lands, carrying [day] and whether it was
/// opened as a typing-first visit. Public (was private to the + sheet) —
/// the dial is now the only door to it.
@visibleForTesting
String scanPathForDay(String? day, {bool typing = false}) {
  final q = <String>[
    if (day != null) 'day=$day',
    if (typing) 'type=1',
  ];
  return q.isEmpty ? '/scan' : '/scan?${q.join('&')}';
}

class _SpeedDialFabState extends ConsumerState<SpeedDialFab> {
  final _fabKey = GlobalKey();
  bool _open = false;
  bool _aiReady = false;

  Future<void> _toggle() async {
    if (_open) {
      Navigator.of(context).maybePop();
      return;
    }
    final box = _fabKey.currentContext!.findRenderObject() as RenderBox;
    final fabTopLeft = box.localToGlobal(Offset.zero);
    final fabSize = box.size;
    final routes = _routes(context, _aiReady);
    setState(() => _open = true);
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Add food',
      // No typed input lives here — the barrier tap-away is correct
      // (input_modal.dart's law is scoped to work that can be lost).
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, __) => _DialOverlay(
        fabTopLeft: fabTopLeft,
        fabSize: fabSize,
        routes: routes,
      ),
    );
    if (mounted) setState(() => _open = false);
  }

  /// Nearest-first by frequency — the item closest to the thumb (last in
  /// this list) is rendered right above the main button.
  List<_DialRoute> _routes(BuildContext context, bool aiReady) => [
        _DialRoute(
          key: const ValueKey('dial-find-food'),
          icon: Icons.search,
          color: AppColors.paprika,
          label: 'Find food',
          onTap: () => showAddSheet(context, day: widget.day),
        ),
        _DialRoute(
          key: const ValueKey('dial-quick-add'),
          icon: Icons.bolt_outlined,
          color: AppColors.butter,
          label: 'Quick add',
          onTap: () => showQuickAddDialog(context, day: widget.day),
        ),
        _DialRoute(
          key: const ValueKey('dial-scan'),
          icon: Icons.qr_code_scanner,
          color: AppColors.sage,
          label: 'Scan',
          onTap: () => context.push(scanPathForDay(widget.day)),
        ),
        _DialRoute(
          key: const ValueKey('dial-type-code'),
          icon: Icons.keyboard_outlined,
          color: AppColors.sage,
          label: 'Type a code',
          onTap: () =>
              context.push(scanPathForDay(widget.day, typing: true)),
        ),
        if (aiReady)
          _DialRoute(
            key: const ValueKey('dial-guess'),
            icon: Icons.auto_awesome,
            color: AppColors.paprika,
            label: 'Guess it',
            onTap: () => showGuessSheet(context, day: widget.day),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    // Watched (not read) so the value is already resolved by the time a
    // tap needs it — the tile exists once a household configured a brain,
    // OR on a device that can label a plate photo (the zero-download CV
    // rung needs no opt-in). valueOrNull, not value: a failed
    // secure-storage read means "no brain", never a crashed dial.
    _aiReady =
        (ref.watch(aiConfigProvider).valueOrNull?.configured ?? false) ||
            (plateScanSupported && ref.watch(plateScannerProvider) != null);
    // Once open, this button sits BEHIND the pushed dial route's own
    // barrier — it stops receiving taps, so it keeps showing '+' rather
    // than a misleadingly-tappable-looking '×'. The real '×' lives in
    // _DialOverlay, positioned exactly over this button's own rect.
    return FloatingActionButton(
      key: _fabKey,
      tooltip: 'Add food',
      onPressed: _open ? null : _toggle,
      child: const Icon(Icons.add),
    );
  }
}

class _DialRoute {
  const _DialRoute({
    required this.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final Key key;
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
}

/// The expanded dial: a scrim (the route already gives us one via
/// `barrierColor`) and a column of labelled circles growing upward from
/// exactly where the compact button sits, on Today or on any past day.
class _DialOverlay extends StatelessWidget {
  const _DialOverlay({
    required this.fabTopLeft,
    required this.fabSize,
    required this.routes,
  });

  final Offset fabTopLeft;
  final Size fabSize;
  final List<_DialRoute> routes;

  static const _gap = AppSpacing.sm + 4; // clears the main button

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            right: media.size.width - (fabTopLeft.dx + fabSize.width),
            bottom: media.size.height - fabTopLeft.dy + _gap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              // Reversed: routes[] is nearest-first (bottom); a Column
              // lays out top-to-bottom, so the farthest route is drawn
              // first to end up highest on screen.
              children: [
                for (final route in routes.reversed) ...[
                  _DialButton(route: route),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
          ),
          // The interactive '×': positioned exactly over the (now inert)
          // compact button underneath, so what looks tappable IS tappable —
          // the compact one lost its taps to this route's own barrier the
          // moment the route was pushed.
          Positioned(
            left: fabTopLeft.dx,
            top: fabTopLeft.dy,
            width: fabSize.width,
            height: fabSize.height,
            child: FloatingActionButton(
              key: const ValueKey('dial-close'),
              heroTag: 'speed-dial-close',
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialButton extends StatelessWidget {
  const _DialButton({required this.route});

  final _DialRoute route;

  @override
  Widget build(BuildContext context) {
    void go() {
      Navigator.of(context).pop();
      route.onTap();
    }

    return Semantics(
      button: true,
      label: route.label,
      child: Row(
        key: route.key,
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: go,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 6),
                child: Text(route.label),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 48dp+ thumb target, per the two-tap law.
          SizedBox(
            width: 48,
            height: 48,
            child: FloatingActionButton.small(
              heroTag: route.key,
              tooltip: route.label,
              backgroundColor: route.color,
              onPressed: go,
              child: Icon(route.icon, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
