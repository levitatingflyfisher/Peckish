import 'package:flutter/material.dart';

/// Modals that hold something you have TYPED.
///
/// One law, two halves: a modal holding typed work never closes on a tap
/// outside itself, and it always shows an obvious way out.
///
/// The bug that earned this (v0.9 phone test): you are typing into a sheet,
/// you swipe over to another app to read a number off a photo, you swipe
/// back — and Android does not restore the keyboard. `viewInsets` drops to
/// zero, every sheet that pads by it shrinks, and the field you had already
/// aimed your thumb at is somewhere else. The tap lands on the scrim and
/// takes the whole entry with it.
///
/// Re-showing the keyboard on resume would be fighting the platform, and
/// the sort of thing that works on one phone and not the next. The moving
/// window is only the commonest way to aim that tap by accident anyway — a
/// thumb on the scrim loses the same data on a phone that never left the
/// foreground. So the fix is at the other end: an ambiguous tap should not
/// be able to destroy work, because a tap outside a form is not a decision
/// to throw it away.
///
/// Dragging the sheet down and the system back button both still close it:
/// those are deliberate, and being hard to leave would be its own bug.
/// Modals with nothing typed in them — a confirm, a portion picker — keep
/// the ordinary tap-away, which is the right gesture for "never mind".
Future<T?> showInputSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useSafeArea = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isDismissible: false,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      builder: builder,
    );

/// The dialog half of the same law. Dialogs already carry a Cancel button,
/// so they need no extra affordance — only the barrier turned off.
Future<T?> showInputDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) =>
    showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: builder,
    );

/// The way out of an input sheet, said plainly. Sheets have no Cancel of
/// their own, so once tapping away stops working there has to be something
/// to tap instead — and it has to be visible without scrolling.
class SheetCloseButton extends StatelessWidget {
  const SheetCloseButton({super.key, this.onClose});

  /// Defaults to popping the sheet with no result.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => IconButton(
        key: const ValueKey('sheet-close'),
        icon: const Icon(Icons.close),
        tooltip: 'Close',
        visualDensity: VisualDensity.compact,
        onPressed: onClose ?? () => Navigator.of(context).pop(),
      );
}
