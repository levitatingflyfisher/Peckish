/// Day-string pretty printing, shared by every screen that names a day
/// ('2026-07-28' → 'Tue · Jul 28'). Hand-rolled on purpose: three arrays
/// beat an intl locale dependency for two labels.
const weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Spelled out for the calendar's own header, where there is room and a
/// month deserves its name.
const monthFullNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String prettyDay(String day) {
  final d = DateTime.parse(day);
  return '${weekdayNames[d.weekday - 1]} · ${monthNames[d.month - 1]} '
      '${d.day}';
}
