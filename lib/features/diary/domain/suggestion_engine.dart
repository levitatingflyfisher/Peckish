import 'package:peckish/features/diary/domain/daily_targets.dart';
import 'package:peckish/features/food/domain/food_usage.dart';
import 'package:peckish/features/food/domain/macro_set.dart';

/// What the engine has to say about the day.
enum SuggestionStatus {
  /// No targets configured — there is nothing to round out.
  noTargets,

  /// Every configured target is already satisfied. Say so, warmly, once.
  complete,

  /// Targets exist and aren't met, but no combination of regulars improves
  /// the day (nothing logged as a regular yet, or the only direction left
  /// is one food can't go). Advisory means the card just stays quiet here.
  quiet,

  /// Concrete ideas, best fit first.
  ideas,
}

/// One food from the regulars, possibly more than once ("2 × Egg").
class SuggestionItem {
  const SuggestionItem({required this.usage, required this.count});

  final FoodUsage usage;
  final int count;
}

/// A combination worth saying out loud: the items, where the day would land,
/// and whether that landing satisfies every configured target.
class Suggestion {
  const Suggestion({
    required this.items,
    required this.after,
    required this.score,
    required this.completesDay,
  });

  final List<SuggestionItem> items;
  final MacroSet after;
  final double score;
  final bool completesDay;
}

class DaySuggestions {
  const DaySuggestions(this.status, [this.ideas = const []]);

  final SuggestionStatus status;
  final List<Suggestion> ideas;
}

/// "Round out your day": exhaustive search over small combinations of the
/// user's own regulars, scored against the remaining targets with per-role
/// ASYMMETRIC penalties — a floor only hurts when short, a cap only when
/// over, "about" hurts both ways. No ratios, no cosine: the combination
/// whose end-of-day totals sit best against the targets wins, and the
/// composition ("protein-dense when protein is short") falls out for free.
///
/// Scale check, because someone will ask: ≤ [maxRegulars] foods in
/// multisets of ≤ [maxCombo] is at most ~5,500 sums of four numbers —
/// microseconds, fully offline, deterministic. (The Settings off-switch
/// exists for trust, not because this is heavy.)
class SuggestionEngine {
  const SuggestionEngine();

  /// The most-used regulars considered; beyond this the tail is noise.
  static const maxRegulars = 30;

  /// Up to three items per idea — a nudge, not a second dinner plan.
  static const maxCombo = 3;

  /// "Satisfied" tolerance: floors count as met at 95%, "about" within ±5%.
  static const tolerance = 0.05;

  /// How many ideas to surface, each led by a different food.
  static const maxIdeas = 3;

  DaySuggestions suggest({
    required DailyTargets targets,
    required MacroSet eaten,
    required List<FoodUsage> regulars,
  }) {
    if (!targets.isSet) return const DaySuggestions(SuggestionStatus.noTargets);

    final axes =
        targets.axes.where((a) => a.target != null).toList(growable: false);
    if (_satisfied(axes, eaten)) {
      return const DaySuggestions(SuggestionStatus.complete);
    }

    // Familiar first, capped, and only foods with something to add.
    final pool = [...regulars]
      ..sort((a, b) {
        final byUse = b.useCount.compareTo(a.useCount);
        return byUse != 0 ? byUse : a.label.compareTo(b.label);
      });
    final foods = pool
        .where((u) =>
            u.macros.kcal != null ||
            u.macros.proteinG != null ||
            u.macros.carbG != null ||
            u.macros.fatG != null)
        .take(maxRegulars)
        .toList(growable: false);
    if (foods.isEmpty) return const DaySuggestions(SuggestionStatus.quiet);

    final baseline = _penalty(axes, eaten);
    final candidates = <Suggestion>[];

    void consider(List<int> picks) {
      var sum = const MacroSet();
      for (final i in picks) {
        sum = sum + foods[i].macros;
      }
      final after = eaten + sum;
      final score = _penalty(axes, after);
      if (score >= baseline - 1e-9) return; // must genuinely help
      final items = <SuggestionItem>[];
      for (final i in picks.toSet()) {
        items.add(SuggestionItem(
            usage: foods[i], count: picks.where((p) => p == i).length));
      }
      candidates.add(Suggestion(
        items: items,
        after: after,
        score: score,
        completesDay: _satisfied(axes, after),
      ));
    }

    for (var i = 0; i < foods.length; i++) {
      consider([i]);
      for (var j = i; j < foods.length; j++) {
        consider([i, j]);
        for (var k = j; k < foods.length; k++) {
          consider([i, j, k]);
        }
      }
    }
    if (candidates.isEmpty) return const DaySuggestions(SuggestionStatus.quiet);

    candidates.sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      if (byScore != 0) return byScore;
      final byCount = _totalItems(a).compareTo(_totalItems(b));
      if (byCount != 0) return byCount;
      final byFamiliar = _familiarity(b).compareTo(_familiarity(a));
      if (byFamiliar != 0) return byFamiliar;
      return _signature(a).compareTo(_signature(b));
    });

    // Diversity: each surfaced idea opens with a different food.
    final ideas = <Suggestion>[];
    final leads = <String>{};
    for (final c in candidates) {
      if (ideas.length == maxIdeas) break;
      if (leads.add(c.items.first.usage.identityKey)) ideas.add(c);
    }
    return DaySuggestions(SuggestionStatus.ideas, ideas);
  }

  static int _totalItems(Suggestion s) =>
      s.items.fold(0, (n, i) => n + i.count);

  static int _familiarity(Suggestion s) =>
      s.items.fold(0, (n, i) => n + i.usage.useCount * i.count);

  static String _signature(Suggestion s) =>
      [for (final i in s.items) '${i.usage.identityKey}x${i.count}'].join('+');

  /// Relative miss per axis under its role, squared and summed. Unknown
  /// eaten values count as zero — same as the day's own display.
  static double _penalty(List<TargetAxis> axes, MacroSet end) {
    var total = 0.0;
    for (final a in axes) {
      final target = a.target!;
      if (target <= 0) continue;
      final value = a.of(end) ?? 0;
      final miss = switch (a.role) {
        TargetRole.about => (value - target).abs(),
        TargetRole.atLeast => value < target ? target - value : 0.0,
        TargetRole.under => value > target ? value - target : 0.0,
      };
      final rel = miss / target;
      total += rel * rel;
    }
    return total;
  }

  static bool _satisfied(List<TargetAxis> axes, MacroSet end) {
    for (final a in axes) {
      final target = a.target!;
      if (target <= 0) continue;
      final value = a.of(end) ?? 0;
      final ok = switch (a.role) {
        TargetRole.about =>
          value >= target * (1 - tolerance) && value <= target * (1 + tolerance),
        TargetRole.atLeast => value >= target * (1 - tolerance),
        TargetRole.under => value <= target * (1 + tolerance),
      };
      if (!ok) return false;
    }
    return true;
  }
}
