import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildNoMeetingRecordKeys,
  buildSubmittedRecordKeys,
  type GroupWeekRecordSubmissionRow,
} from './groupWeekRecordSubmissions.ts';

const rows: GroupWeekRecordSubmissionRow[] = [
  {
    week_id: 'week-1',
    group_id: 'group-1',
    attendance_submitted_at: '2026-01-04T10:00:00Z',
    prayer_submitted_at: null,
  },
  {
    week_id: 'week-2',
    group_id: 'group-1',
    attendance_submitted_at: null,
    prayer_submitted_at: '2026-01-11T10:00:00Z',
  },
  {
    week_id: 'week-3',
    group_id: 'group-2',
    attendance_submitted_at: '2026-01-18T10:00:00Z',
    prayer_submitted_at: '2026-01-18T10:00:00Z',
  },
  {
    week_id: 'week-4',
    group_id: 'new-family-group',
    attendance_submitted_at: '2026-01-25T10:00:00Z',
    prayer_submitted_at: '2026-01-25T10:00:00Z',
    attendance_submission_kind: 'no_meeting',
    prayer_submission_kind: 'no_meeting',
  },
];

test('attendance submission keys come only from explicit attendance markers', () => {
  const keys = buildSubmittedRecordKeys(rows, 'attendance');

  assert.deepEqual([...keys].sort(), ['week-1:group-1', 'week-3:group-2', 'week-4:new-family-group']);
});

test('prayer submission keys come only from explicit prayer markers', () => {
  const keys = buildSubmittedRecordKeys(rows, 'prayer');

  assert.deepEqual([...keys].sort(), ['week-2:group-1', 'week-3:group-2', 'week-4:new-family-group']);
});

test('no-meeting keys come only from no-meeting submission kinds', () => {
  const attendanceKeys = buildNoMeetingRecordKeys(rows, 'attendance');
  const prayerKeys = buildNoMeetingRecordKeys(rows, 'prayer');

  assert.deepEqual([...attendanceKeys], ['week-4:new-family-group']);
  assert.deepEqual([...prayerKeys], ['week-4:new-family-group']);
});
