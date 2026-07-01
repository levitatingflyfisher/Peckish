import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/recipes/presentation/recipes_screen.dart';
import 'package:peckish/shared/theme/app_colors.dart';
import 'package:peckish/shared/theme/app_spacing.dart';
import 'package:peckish/shared/widgets/confirm_dialog.dart';

class RecipeDetailScreen extends ConsumerWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipe = ref.watch(_recipeProvider(recipeId));
    final r = recipe.value;
    if (r == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final text = Theme.of(context).textTheme;
    final per = r.perServing;

    return Scaffold(
      appBar: AppBar(
        title: Text(r.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => RecipeEditScreen(existing: r)));
              ref.invalidate(_recipeProvider(recipeId));
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () async {
              final confirmed = await showConfirmDialog(
                context,
                title: 'Delete "${r.title}"?',
                message: 'The recipe leaves the box. Meals already logged '
                    'and plans already made keep their own copies.',
              );
              if (!confirmed) return;
              await ref.read(recipeRepositoryProvider).delete(recipeId);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (r.servings != null)
                Chip(
                    label: Text(
                        '${r.servings! % 1 == 0 ? r.servings!.toInt() : r.servings} servings')),
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
                style: text.bodySmall?.copyWith(color: AppColors.stone)),
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
            Text(r.instructions, style: text.bodyLarge?.copyWith(height: 1.5)),
          ],
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }
}

final _recipeProvider = FutureProvider.autoDispose.family(
    (ref, String id) => ref.watch(recipeRepositoryProvider).byId(id));
