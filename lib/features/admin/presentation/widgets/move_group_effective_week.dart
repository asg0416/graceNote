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
  DateTime? currentWeek,
}) {
  var resolved = weekStart(requestedWeek);
  final start = seasonStartWeek == null ? null : weekStart(seasonStartWeek);
  final end = seasonEndWeek == null ? null : weekStart(seasonEndWeek);
  final current = currentWeek == null ? null : weekStart(currentWeek);

  if (start != null && resolved.isBefore(start)) {
    resolved = start;
  }
  DateTime? latest = end;
  if (current != null && (latest == null || current.isBefore(latest))) {
    latest = current;
  }
  if (start != null && latest != null && latest.isBefore(start)) {
    latest = start;
  }
  if (latest != null && resolved.isAfter(latest)) {
    resolved = latest;
  }
  return resolved;
}
