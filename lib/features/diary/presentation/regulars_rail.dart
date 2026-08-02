import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:peckish/core/providers/core_providers.dart';
import 'package:peckish/features/diary/domain/diary_entry.dart';
import 'package:peckish/features/diary/domain/relog.dart';
import 'package:peckish/features/diary/presentation/day_format.dart';
import 'package:peckish/shared/extensions/qty_format.dart';
import 'package:peckish/shared/theme/app_spacing.dart';

/// The regulars: the foods this household actually reaches for, offered as
/// one-tap relogs.
///
/// Logging something you have logged before is the commonest way to add
/// anything, so it is first-class on EVERY surface that adds food — Today,
/// any past day, and the + sheet — and every one of them aims at the day it
/// was opened on. (v0.8 shipped this rail on Today alone, hardcoded to
/// `DateTime.now()`; a missed day could only be filled by typing a search.)
///
/// The rail's own regulars, live — reacts to hides/unhides made anywhere
/// (the Foods screen), not just to diary writes. The twelve-chip cap lives
/// in the query, so the rail costs twelve rows per change, not every habit
/// ever recorded.
final regularsProvider = StreamProvider.autoDispose<List<DiaryEntry>>((ref) =>
    ref
        .watch(foodUsageRepositoryProvider)
        .watchVisible(limit: 12)
        .map((us) => [for (final u in us) u.asTemplateEntry()]));

/// Log a regular onto [day] (null = today) and say so. The only writer for
/// every one-tap path — see [relogEntry] for why the rule is shared.
Future<void> logRegular(
  BuildContext context,
  WidgetRef ref,
  DiaryEntry template, {
  String? day,
}) async {
  await ref
      .read(diaryRepositoryProvider)
      .log(relogEntry(template, day: day));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(day == null
          ? 'Logged ${template.label}'
          // Naming the day is the whole point on a past day: a silent
          // confirmation there reads as "did that go to today?".
          : 'Logged ${template.label} to ${prettyDay(day)}'),
    ));
}

/// The horizontal chip rail — Today's signature, and every past day's.
class RegularsRail extends ConsumerWidget {
  const RegularsRail({super.key, this.day});

  /// Null = today; otherwise the past day every chip feeds.
  final String? day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regulars = ref.watch(regularsProvider).value ?? const <DiaryEntry>[];
    if (regulars.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Your regulars',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton(
              onPressed: () => context.push('/foods'),
              child: const Text('See all'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: regulars.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) {
              final template = regulars[i];
              return ActionChip(
                avatar: const Icon(Icons.replay, size: 18),
                label: Text(template.label, overflow: TextOverflow.ellipsis),
                labelPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                onPressed: () => logRegular(context, ref, template, day: day),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The same regulars as a vertical list, for the + sheet — where there is
/// room to show the portion each tap will log, and where a one-handed
/// thumb wants targets stacked rather than scrolled sideways.
class RegularsList extends ConsumerWidget {
  const RegularsList({super.key, this.day, this.onLogged});

  final String? day;

  /// Called after a line lands — the sheet closes itself.
  final VoidCallback? onLogged;

  /// Enough to cover the habits, short enough that Quick add and the
  /// scanner stay on the first screenful.
  static const max = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regulars = ref.watch(regularsProvider).value ?? const <DiaryEntry>[];
    if (regulars.isEmpty) return const SizedBox.shrink();
    final shown = regulars.take(max).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Text('Your regulars',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              TextButton(
                onPressed: () {
                  onLogged?.call();
                  context.push('/foods');
                },
                child: const Text('See all'),
              ),
            ],
          ),
        ),
        for (final template in shown)
          ListTile(
            leading: const Icon(Icons.replay),
            title: Text(template.label),
            subtitle: Text(_portion(template)),
            onTap: () async {
              await logRegular(context, ref, template, day: day);
              onLogged?.call();
            },
          ),
        const Divider(),
      ],
    );
  }

  /// '1 bowl · 320 kcal' — what this tap will actually log, so the list is
  /// a decision and not a guess.
  static String _portion(DiaryEntry t) {
    final amount = '${formatQty(t.qty)} ${t.unitLabel}';
    final kcal = t.macros.kcal;
    return kcal == null ? amount : '$amount · ${kcal.round()} kcal';
  }
}
