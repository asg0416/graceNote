class AttendanceSummary {
  final int presentCount;
  final int totalCount;

  const AttendanceSummary({
    required this.presentCount,
    required this.totalCount,
  });

  int get ratePercent =>
      totalCount > 0 ? (presentCount / totalCount * 100).round() : 0;
}

String? attendancePersonKey(Map<String, dynamic> row) {
  final personId = row['person_id']?.toString();
  if (personId != null && personId.isNotEmpty) return 'person:$personId';

  final directoryId =
      row['directory_member_id']?.toString() ?? row['id']?.toString();
  if (directoryId != null && directoryId.isNotEmpty) {
    return 'directory:$directoryId';
  }

  final profileId = row['profile_id']?.toString();
  if (profileId != null && profileId.isNotEmpty) return 'profile:$profileId';

  return null;
}

bool isAttendancePresent(dynamic status) =>
    status == 'present' || status == 'late';

AttendanceSummary summarizeAttendanceRows(Iterable<Map<String, dynamic>> rows) {
  final totalKeys = <String>{};
  final presentKeys = <String>{};

  for (final row in rows) {
    final key = attendancePersonKey(row);
    if (key == null) continue;

    totalKeys.add(key);
    if (isAttendancePresent(row['status'])) {
      presentKeys.add(key);
    }
  }

  return AttendanceSummary(
    presentCount: presentKeys.length,
    totalCount: totalKeys.length,
  );
}

AttendanceSummary summarizeSubmittedDepartmentAttendance(
  Iterable<Map<String, dynamic>> groups,
) {
  final rows = <Map<String, dynamic>>[];

  for (final group in groups) {
    if (group['is_submitted'] != true) continue;

    final members = group['members'];
    if (members is! Iterable) continue;

    for (final member in members) {
      if (member is Map<String, dynamic>) {
        rows.add(member);
      } else if (member is Map) {
        rows.add(Map<String, dynamic>.from(member));
      }
    }
  }

  return summarizeAttendanceRows(rows);
}
