import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

// The delete policy, in one place (fleet ruling, 2026-09-26):
//
// * An EASY gesture that deletes (a swipe on a diary line or a grocery row)
//   asks first, with showOhConfirm naming the thing, because a thumb can do
//   it by accident.
// * A DELIBERATE delete (a Delete button, a menu item, the × on a plan
//   entry, "Clear checked") does not ask. It happens at once and offers
//   Undo through the bar below, which never times out: it stays until the
//   person taps Undo, dismisses it, or deletes something else.
//
// The words (lens audit writing-10): "Remove" takes a line off a list (a
// plan entry, a grocery item); "Delete" destroys a thing the household made
// (a recipe, a custom food, a logged diary line). The bar says what
// happened in the same word.

/// The one Undo offer for the whole app.
///
/// Deliberate deletes often close the screen they happen on (a recipe's
/// page, the fix-this-line sheet), so a bar placed on that screen would
/// vanish with it. The controller lives as long as the app and [UndoHost]
/// shows its bar below every screen.
///
/// Read it BEFORE awaiting the delete: the row that asked usually leaves
/// the tree with the delete, and a disposed widget's `ref` throws.
final undoControllerProvider = Provider<OhUndoController>((ref) {
  final controller = OhUndoController();
  ref.onDispose(controller.dispose);
  return controller;
});

/// Wraps the app's navigator (from `MaterialApp.builder`) and keeps the
/// pending Undo bar pinned under it. It never times out.
class UndoHost extends ConsumerStatefulWidget {
  const UndoHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UndoHost> createState() => _UndoHostState();
}

class _UndoHostState extends ConsumerState<UndoHost> {
  // The bar's buttons carry tooltips, which need an Overlay; the navigator's
  // own overlay sits below this widget, so the host brings one.
  late final OverlayEntry _entry = OverlayEntry(builder: _buildFrame);

  @override
  void didUpdateWidget(UndoHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child != widget.child) _entry.markNeedsBuild();
  }

  Widget _buildFrame(BuildContext context) {
    final controller = ref.read(undoControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final showing = controller.pending != null;
        return Column(
          children: [
            Expanded(
              // While the bar shows it takes the bottom safe area, so the
              // screen above does not pad for the gesture bar a second
              // time. The tree shape stays the same either way, so the
              // navigator keeps its state.
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: showing,
                child: widget.child,
              ),
            ),
            OhUndoBar(controller: controller, commitOnDispose: false),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(initialEntries: [_entry]);
  }
}
