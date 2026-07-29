/// User preferences persisted in the local drift key→value store.
///
/// Holds only app-shell toggles (theme, the suggestion card's switch and
/// its per-day dismissal). Domain data — foods, diary entries, recipes,
/// plans — lives in its own tables, never here.
class UserPrefs {
  const UserPrefs({
    this.isDarkMode = false,
    this.suggestionsEnabled = true,
    this.suggestionsDismissedDay,
  });

  final bool isDarkMode;

  /// The "Round out your day" master switch (Settings › Your day).
  final bool suggestionsEnabled;

  /// The day ('YYYY-MM-DD') the card was last dismissed for — it stays
  /// quiet for that day and returns with the next one.
  final String? suggestionsDismissedDay;
}
