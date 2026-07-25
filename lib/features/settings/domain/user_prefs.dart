/// User preferences persisted in the local drift key→value store.
///
/// Holds only app-shell toggles (theme). Domain data — foods, diary entries,
/// recipes, plans — lives in its own tables, never here.
class UserPrefs {
  const UserPrefs({this.isDarkMode = false});

  final bool isDarkMode;
}
