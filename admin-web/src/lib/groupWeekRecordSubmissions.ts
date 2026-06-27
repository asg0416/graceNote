export type RecordSubmissionKind = 'attendance' | 'prayer';

export type GroupWeekRecordSubmissionRow = {
  week_id?: string | null;
  group_id?: string | null;
  attendance_submitted_at?: string | null;
  prayer_submitted_at?: string | null;
};

export const buildWeekGroupKey = (weekId: string, groupId: string) => `${weekId}:${groupId}`;

export const buildSubmittedRecordKeys = (
  rows: GroupWeekRecordSubmissionRow[],
  kind: RecordSubmissionKind
) => {
  const keys = new Set<string>();

  rows.forEach((row) => {
    if (!row.week_id || !row.group_id) return;
    const submittedAt = kind === 'attendance'
      ? row.attendance_submitted_at
      : row.prayer_submitted_at;
    if (!submittedAt) return;
    keys.add(buildWeekGroupKey(row.week_id, row.group_id));
  });

  return keys;
};
