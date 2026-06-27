import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/core/utils/record_completion_status.dart';

void main() {
  group('resolveRecordCompletionStatus', () {
    test('marks a week red when attendance was not submitted', () {
      final status = resolveRecordCompletionStatus(
        isActiveWeek: true,
        isNoMeetingWeek: false,
        isFutureWeek: false,
        submittedAttendanceCount: 0,
        publishedPrayerCount: 0,
      );

      expect(status, RecordCompletionStatus.attendanceMissing);
    });

    test('uses explicit attendance marker count as submission', () {
      final status = resolveRecordCompletionStatus(
        isActiveWeek: true,
        isNoMeetingWeek: false,
        isFutureWeek: false,
        submittedAttendanceCount: 12,
        publishedPrayerCount: 2,
      );

      expect(status, RecordCompletionStatus.normal);
    });

    test(
        'marks a week as prayer-missing when only published prayers are missing',
        () {
      final status = resolveRecordCompletionStatus(
        isActiveWeek: true,
        isNoMeetingWeek: false,
        isFutureWeek: false,
        submittedAttendanceCount: 12,
        publishedPrayerCount: 0,
      );

      expect(status, RecordCompletionStatus.prayerMissing);
    });

    test('keeps completed and non-actionable weeks visually normal', () {
      expect(
        resolveRecordCompletionStatus(
          isActiveWeek: true,
          isNoMeetingWeek: false,
          isFutureWeek: false,
          submittedAttendanceCount: 12,
          publishedPrayerCount: 3,
        ),
        RecordCompletionStatus.normal,
      );
      expect(
        resolveRecordCompletionStatus(
          isActiveWeek: true,
          isNoMeetingWeek: true,
          isFutureWeek: false,
          submittedAttendanceCount: 0,
          publishedPrayerCount: 0,
        ),
        RecordCompletionStatus.normal,
      );
      expect(
        resolveRecordCompletionStatus(
          isActiveWeek: true,
          isNoMeetingWeek: false,
          isFutureWeek: true,
          submittedAttendanceCount: 0,
          publishedPrayerCount: 0,
        ),
        RecordCompletionStatus.normal,
      );
      expect(
        resolveRecordCompletionStatus(
          isActiveWeek: false,
          isNoMeetingWeek: false,
          isFutureWeek: false,
          submittedAttendanceCount: 0,
          publishedPrayerCount: 0,
        ),
        RecordCompletionStatus.normal,
      );
    });
  });
}
