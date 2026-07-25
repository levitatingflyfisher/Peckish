/// Where on the day a planned thing sits.
enum PlanSlot { breakfast, lunch, dinner, other }

/// What a plan cell points at: a recipe from the box, a saved staple, or a
/// free-text note — "Leftovers" and "Pizza out" are first-class plans, not
/// gaps.
enum PlanKind { recipe, meal, note }

/// One cell of the week. [title] is resolved at read time from the live
/// recipe/meal (or the note text) — the plan never snapshots names, because a
/// renamed recipe should rename on the calendar too.
class PlanEntry {
  const PlanEntry({
    required this.id,
    required this.day,
    required this.slot,
    required this.kind,
    this.refId,
    this.note,
    this.title = '',
  });

  final String id;

  /// Local calendar day 'YYYY-MM-DD'.
  final String day;
  final PlanSlot slot;
  final PlanKind kind;

  /// Recipe id or saved-meal id, per [kind]; null for notes.
  final String? refId;
  final String? note;

  /// Resolved display title (read-side only; ignored on write).
  final String title;
}
