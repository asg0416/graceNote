import assert from 'node:assert/strict';
import test from 'node:test';
import {
  calculateWeekAttendanceMetrics,
  getActiveRosterForWeek,
  sortRosterForDisplay,
  type AttendanceRosterMember,
} from './attendanceMetrics.ts';

const roster: AttendanceRosterMember[] = [
  {
    directoryMemberId: 'dir-a-current',
    personId: 'person-a',
    fullName: '김보영',
    groupName: '동준 상희 조',
    spouseName: '유성열',
    startsAt: '2026-02-02T00:00:00Z',
  },
  {
    directoryMemberId: 'dir-a-old',
    personId: 'person-a',
    fullName: '김보영',
    groupName: '새가족조',
    spouseName: '유성열',
    startsAt: '2026-01-31T00:00:00Z',
    endsAt: '2026-02-01T00:00:00Z',
  },
  {
    directoryMemberId: 'dir-b',
    personId: 'person-b',
    fullName: '유성열',
    groupName: '동준 상희 조',
    spouseName: '김보영',
    startsAt: '2026-01-01T00:00:00Z',
  },
];

test('active roster is selected by week date, not current row state', () => {
  assert.deepEqual(
    getActiveRosterForWeek(roster, '2026-01-25').map((member) => member.fullName),
    ['유성열']
  );

  assert.deepEqual(
    getActiveRosterForWeek(roster, '2026-02-08').map((member) => member.directoryMemberId),
    ['dir-a-current', 'dir-b']
  );
});

test('weekly denominator uses distinct active people for that week', () => {
  const metrics = calculateWeekAttendanceMetrics({
    weekDate: '2026-02-08',
    roster,
    attendance: [
      { directoryMemberId: 'dir-a-current', status: 'present' },
      { directoryMemberId: 'dir-a-current', status: 'late' },
      { directoryMemberId: 'dir-b', status: 'absent' },
    ],
  });

  assert.equal(metrics.totalPeople, 2);
  assert.equal(metrics.presentPeople, 1);
  assert.equal(metrics.absentPeople, 1);
  assert.equal(metrics.rate, 50);
});

test('historical attendance snapshot participates in denominator even before reconstructed startsAt', () => {
  const metrics = calculateWeekAttendanceMetrics({
    weekDate: '2026-01-25',
    roster,
    attendance: [
      { directoryMemberId: 'dir-a-current', status: 'present' },
      { directoryMemberId: 'dir-b', status: 'absent' },
    ],
  });

  assert.equal(metrics.totalPeople, 2);
  assert.equal(metrics.presentPeople, 1);
  assert.equal(metrics.rate, 50);
});

test('late counts as attendance and no-meeting days have no denominator', () => {
  const lateMetrics = calculateWeekAttendanceMetrics({
    weekDate: '2026-02-08',
    roster,
    attendance: [{ directoryMemberId: 'dir-b', status: 'late' }],
  });

  assert.equal(lateMetrics.presentPeople, 1);

  const noMeetingMetrics = calculateWeekAttendanceMetrics({
    weekDate: '2026-04-19',
    roster,
    attendance: [{ directoryMemberId: 'dir-b', status: 'present' }],
    noMeetingDates: new Set(['2026-04-19']),
  });

  assert.equal(noMeetingMetrics.totalPeople, 0);
  assert.equal(noMeetingMetrics.rate, null);
  assert.equal(noMeetingMetrics.isNoMeetingDay, true);
});

test('couple-mode roster sorting keeps spouses together inside the same group', () => {
  const sorted = sortRosterForDisplay([
    { directoryMemberId: '1', personId: '1', fullName: '박민영', groupName: '일반조' },
    { directoryMemberId: '2', personId: '2', fullName: '유성열', groupName: '동준 상희 조', spouseName: '김보영' },
    { directoryMemberId: '3', personId: '3', fullName: '김보영', groupName: '동준 상희 조', spouseName: '유성열' },
  ]);

  assert.deepEqual(sorted.map((member) => member.fullName), ['김보영', '유성열', '박민영']);
});
