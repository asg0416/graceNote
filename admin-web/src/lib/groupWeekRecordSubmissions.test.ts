import assert from 'node:assert/strict';
import test from 'node:test';
import {
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
];

test('attendance submission keys come only from explicit attendance markers', () => {
  const keys = buildSubmittedRecordKeys(rows, 'attendance');

  assert.deepEqual([...keys].sort(), ['week-1:group-1', 'week-3:group-2']);
});

test('prayer submission keys come only from explicit prayer markers', () => {
  const keys = buildSubmittedRecordKeys(rows, 'prayer');

  assert.deepEqual([...keys].sort(), ['week-2:group-1', 'week-3:group-2']);
});
