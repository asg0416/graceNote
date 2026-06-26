import 'package:flutter_test/flutter_test.dart';
import 'package:grace_note/core/utils/attendance_summary.dart';

void main() {
  test('department summary counts multi-assigned people once', () {
    final groups = [
      {
        'id': 'new-member-group',
        'is_submitted': true,
        'members': [
          {
            'id': 'directory-1a',
            'person_id': 'person-1',
            'status': 'present',
          },
          {
            'id': 'directory-2',
            'person_id': 'person-2',
            'status': 'absent',
          },
        ],
      },
      {
        'id': 'regular-group',
        'is_submitted': true,
        'members': [
          {
            'id': 'directory-1b',
            'person_id': 'person-1',
            'status': 'present',
          },
          {
            'id': 'directory-3',
            'person_id': 'person-3',
            'status': 'late',
          },
        ],
      },
    ];

    final summary = summarizeSubmittedDepartmentAttendance(groups);

    expect(summary.totalCount, 3);
    expect(summary.presentCount, 2);
    expect(summary.ratePercent, 67);
  });
}
