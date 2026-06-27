enum RecordCompletionStatus {
  normal,
  attendanceMissing,
  prayerMissing,
}

RecordCompletionStatus resolveRecordCompletionStatus({
  required bool isActiveWeek,
  required bool isNoMeetingWeek,
  required bool isFutureWeek,
  required int submittedAttendanceCount,
  required int publishedPrayerCount,
}) {
  if (!isActiveWeek || isNoMeetingWeek || isFutureWeek) {
    return RecordCompletionStatus.normal;
  }
  if (submittedAttendanceCount <= 0) {
    return RecordCompletionStatus.attendanceMissing;
  }
  if (publishedPrayerCount <= 0) {
    return RecordCompletionStatus.prayerMissing;
  }
  return RecordCompletionStatus.normal;
}
