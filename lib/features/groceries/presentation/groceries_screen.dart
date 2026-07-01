import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/groceries/domain/grocery_item.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groceries'),
        actions: [
          IconButton(
            icon: const Icon(Icons.remove_done),
            tooltip: 'Clear checked',
            onPressed: () => ref.read(groceryRepositoryProvider).clearChecked(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          const _AddField(),
          const SizedBox(height: AppSpacing.md),
          if ((items.value ?? const []).isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                'The list is empty. Plan the week, then "Set the table" — '
                'or add things by hand above.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.stone),
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
                          ?.copyWith(color: AppColors.jam)),
                ),
                for (final item in byAisle[aisle]!)
                  _ItemRow(item: item),
              ],
          const SizedBox(height: 96),
        ],
      ),
    );
  }
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
      onDismissed: (_) => ref.read(groceryRepositoryProvider).remove(item.id),
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
                          color: AppColors.stone)
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
