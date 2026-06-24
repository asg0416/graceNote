DateTime weekStart(DateTime date) {
  return DateTime(date.year, date.month, date.day)
      .subtract(Duration(days: date.weekday % 7));
}

DateTime? parseWeekDateText(dynamic value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value.toString());
  return parsed == null ? null : weekStart(parsed);
}

DateTime resolveMoveEffectiveWeek({
  required DateTime requestedWeek,
  DateTime? seasonStartWeek,
  DateTime? seasonEndWeek,
}) {
  var resolved = weekStart(requestedWeek);
  final start = seasonStartWeek == null ? null : weekStart(seasonStartWeek);
  final end = seasonEndWeek == null ? null : weekStart(seasonEndWeek);

  if (start != null && resolved.isBefore(start)) {
    resolved = start;
  }
  if (end != null && resolved.isAfter(end)) {
    resolved = end;
  }
  return resolved;
}
