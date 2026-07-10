enum RecordSubmissionKind {
  attendance,
  prayer,
}

bool isRecordNoMeetingSubmission(
  Map<String, dynamic>? submission,
  RecordSubmissionKind kind,
) {
  if (submission == null) return false;

  final submittedAt = kind == RecordSubmissionKind.attendance
      ? submission['attendance_submitted_at']
      : submission['prayer_submitted_at'];
  final submissionKind = kind == RecordSubmissionKind.attendance
      ? submission['attendance_submission_kind']
      : submission['prayer_submission_kind'];

  return submittedAt != null && submissionKind == 'no_meeting';
}

bool shouldPromptAttendanceCheck({
  required Iterable<Map<String, dynamic>> members,
  required bool attendanceNoMeetingSubmitted,
}) {
  if (attendanceNoMeetingSubmitted) return false;
  if (members.isEmpty) return false;
  return !members.any((member) => member['isPresent'] == true);
}
