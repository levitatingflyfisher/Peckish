import 'package:flutter/material.dart';
import 'package:openhearth_design/openhearth_design.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/extensions/qty_format.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/undo_host.dart';

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipe = ref.watch(_recipeProvider(recipeId));
    final r = recipe.value;
    if (r == null) {
      return const Scaffold(
          body: OhPage(
              padding: EdgeInsets.zero,
              child: Center(child: CircularProgressIndicator())));
    }
    final text = Theme.of(context).textTheme;
    final per = r.perServing;

    return Scaffold(
      appBar: AppBar(
        title: Text(r.title, overflow: TextOverflow.ellipsis),
        actions: [
          OhBarActions(children: [
            // Icon plus a short word (fleet ruling on top bars).
            OhBarAction(
              icon: Icons.edit_outlined,
              label: 'Edit',
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => RecipeEditScreen(existing: r)));
                ref.invalidate(_recipeProvider(recipeId));
              },
            ),
            // Deliberate, so it does not ask (fleet delete ruling): the page
            // closes and the app-wide Undo re-seats the recipe, ingredients
            // and all. Meals already logged and plans already made keep their
            // own copies either way.
            OhBarAction(
              icon: Icons.delete_outline,
              label: 'Delete',
              onPressed: () async {
                final repo = ref.read(recipeRepositoryProvider);
                final undo = ref.read(undoControllerProvider);
                await repo.delete(recipeId);
                if (context.mounted) Navigator.of(context).pop();
                undo.show(
                  message: 'Deleted “${r.title}”',
                  onUndo: () => repo.restore(r),
                );
              },
            ),
          ]),
        ],
      ),
      body: OhPage(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  if (r.servings != null)
                    Chip(label: Text('${formatQty(r.servings!)} servings')),
                  if (per?.kcal != null)
                    Chip(
                      avatar: const CircleAvatar(
                          backgroundColor: AppColors.butter, radius: 6),
                      label: Text('${per!.kcal!.round()} kcal/serving'),
                    ),
                  if (per?.proteinG != null)
                    Chip(label: Text('${per!.proteinG!.round()}g protein')),
                ],
              ),
              if (r.sourceUrl != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(r.sourceUrl!,
                    style: text.bodySmall
                        ?.copyWith(color: AppColors.secondaryText(context))),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text('Ingredients', style: text.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              for (final i in r.ingredients)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 7, right: AppSpacing.sm),
                        child: CircleAvatar(
                            radius: 3, backgroundColor: AppColors.sage),
                      ),
                      Expanded(child: Text(i.text, style: text.bodyLarge)),
                    ],
                  ),
                ),
              if (r.instructions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Instructions', style: text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(r.instructions,
                    style: text.bodyLarge?.copyWith(height: 1.5)),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          )),
    );
  }
}

final _recipeProvider = FutureProvider.autoDispose
    .family((ref, String id) => ref.watch(recipeRepositoryProvider).byId(id));
