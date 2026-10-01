import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/features/plan/domain/week.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/theme_toggle_action.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

/// The list, walked aisle by aisle. Whole-row tap targets (the Furrow
/// lesson: checkboxes are for thumbs, not cursors).
class GroceriesScreen extends ConsumerWidget {
  const GroceriesScreen({super.key});

  static const _aisleNames = {
    GroceryAisle.produce: 'Produce',
    GroceryAisle.meat: 'Meat & fish',
    GroceryAisle.dairy: 'Dairy & eggs',
    GroceryAisle.bakery: 'Bakery',
    GroceryAisle.frozen: 'Frozen',
    GroceryAisle.pantry: 'Pantry',
    GroceryAisle.other: 'Everything else',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(_itemsProvider);
    final byAisle = <GroceryAisle, List<GroceryItem>>{};
    for (final item in items.value ?? const <GroceryItem>[]) {
      byAisle.putIfAbsent(item.aisle, () => []).add(item);
    }

    final anyChecked =
        (items.value ?? const <GroceryItem>[]).any((i) => i.checked);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groceries'),
        actions: const [OhBarActions(children: [ThemeToggleAction()])],
      ),
      body: OhPage(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              const _AddField(),
              // A word, not a glyph whose only name is a tooltip a thumb
              // never sees (lens audit dmmt-07), shown only when there is
              // something to clear. It lives in the page, beside the list
              // it acts on, not in a bar that cannot fit it at large text.
              // Deliberate, so it does not ask: it reports its scope and
              // hands it back (humane-05).
              if (anyChecked)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    icon: const Icon(Icons.remove_done),
                    label: const Text('Clear checked'),
                    onPressed: () => _clearChecked(ref),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              if ((items.value ?? const []).isEmpty)
                // The act, not a description of it (lens audit dmmt-08,
                // finding 3): the same regenerate path and the same week as
                // Plan's Set the table, from the one screen that needs it.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'The list is empty. Build it from the dinners planned '
                        'this week, or add things by hand above.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.secondaryText(context)),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton.icon(
                        icon: const Icon(Icons.shopping_basket_outlined),
                        label:
                            const Text('Set the table from this week’s plan'),
                        style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52)),
                        onPressed: () => ref
                            .read(groceryRepositoryProvider)
                            .regenerateFromPlan(
                                weekDays(mondayOf(DateTime.now()))),
                      ),
                    ],
                  ),
                )
              else
                for (final aisle in GroceryAisle.values)
                  if (byAisle.containsKey(aisle)) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                          top: AppSpacing.md, bottom: AppSpacing.xs),
                      child: Text(_aisleNames[aisle]!,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppColors.paprika)),
                    ),
                    for (final item in byAisle[aisle]!) _ItemRow(item: item),
                  ],
              const SizedBox(height: 96),
            ],
          )),
    );
  }
}

Future<void> _clearChecked(WidgetRef ref) async {
  final repo = ref.read(groceryRepositoryProvider);
  final undo = ref.read(undoControllerProvider);
  final cleared = await repo.clearChecked();
  if (cleared.isEmpty) return;
  undo.show(
    message: cleared.length == 1
        ? 'Cleared 1 checked item'
        : 'Cleared ${cleared.length} checked items',
    onUndo: () => repo.restore(cleared),
  );
}

final _itemsProvider = StreamProvider.autoDispose(
    (ref) => ref.watch(groceryRepositoryProvider).watchAll());

/// The add field clears itself on submit so the next item can follow
/// immediately (and the typed text doesn't linger as a ghost).
class _AddField extends ConsumerStatefulWidget {
  const _AddField();

  @override
  ConsumerState<_AddField> createState() => _AddFieldState();
}

class _AddFieldState extends ConsumerState<_AddField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.add),
        hintText: 'Add something…',
        border: OutlineInputBorder(),
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (value) async {
        final name = value.trim();
        if (name.isEmpty) return;
        _controller.clear();
        await ref.read(groceryRepositoryProvider).addManual(name);
      },
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({required this.item});

  final GroceryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        color: AppColors.clay,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      // A swipe is an easy gesture, used one-handed in a shop: it asks
      // first, naming the item, and the removal can still be undone.
      confirmDismiss: (_) => showOhConfirm(
        context,
        title: 'Remove ${item.name}?',
        confirmLabel: 'Remove item',
        confirmColor: AppColors.clay,
      ),
      onDismissed: (_) async {
        // Read both before the await: the row leaves the tree with the
        // delete, and a disposed ConsumerWidget's ref throws.
        final repo = ref.read(groceryRepositoryProvider);
        final undo = ref.read(undoControllerProvider);
        await repo.remove(item.id);
        undo.show(
          message: 'Removed ${item.name}',
          onUndo: () => repo.restore([item.id]),
        );
      },
      child: InkWell(
        onTap: () => ref
            .read(groceryRepositoryProvider)
            .setChecked(item.id, checked: !item.checked),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              // Big, thumb-scale check target.
              SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  item.checked
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: item.checked ? AppColors.sage : AppColors.stone,
                  size: 28,
                ),
              ),
              Expanded(
                child: Text(
                  item.name,
                  style: item.checked
                      ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                          decoration: TextDecoration.lineThrough,
                          color: AppColors.secondaryText(context))
                      : Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (item.manual)
                const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: Icon(Icons.push_pin_outlined,
                      size: 16, color: AppColors.stone),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
