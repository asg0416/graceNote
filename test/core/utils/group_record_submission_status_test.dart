import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/core/utils/group_record_submission_status.dart';

void main() {
  test('detects no-meeting submission only with timestamp and explicit kind',
      () {
    expect(
      isRecordNoMeetingSubmission(
        {
          'attendance_submitted_at': '2026-07-05T10:00:00Z',
          'attendance_submission_kind': 'no_meeting',
        },
        RecordSubmissionKind.attendance,
      ),
      isTrue,
    );

    expect(
      isRecordNoMeetingSubmission(
        {
          'attendance_submitted_at': null,
          'attendance_submission_kind': 'no_meeting',
        },
        RecordSubmissionKind.attendance,
      ),
      isFalse,
    );

    expect(
      isRecordNoMeetingSubmission(
        {
          'prayer_submitted_at': '2026-07-05T10:00:00Z',
          'prayer_submission_kind': 'records',
        },
        RecordSubmissionKind.prayer,
      ),
      isFalse,
    );
  });

  test(
      'does not prompt attendance check after no-meeting attendance submission',
      () {
    expect(
      shouldPromptAttendanceCheck(
        members: [
          {'isPresent': false},
          {'isPresent': false},
        ],
        attendanceNoMeetingSubmitted: true,
      ),
      isFalse,
    );
  });

  test('prompts attendance check when there is no attendance submission', () {
    expect(
      shouldPromptAttendanceCheck(
        members: [
          {'isPresent': false},
          {'isPresent': false},
        ],
        attendanceNoMeetingSubmitted: false,
      ),
      isTrue,
    );
  });
}
