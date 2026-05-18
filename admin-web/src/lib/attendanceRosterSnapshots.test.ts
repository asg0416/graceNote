import assert from 'node:assert/strict';
import test from 'node:test';
import {
  calculateSnapshotMetrics,
  groupSnapshotMembersForDisplay,
  mapSnapshotMemberRow,
  type AttendanceRosterSnapshotMember,
} from './attendanceRosterSnapshots.ts';

const members: AttendanceRosterSnapshotMember[] = [
  {
    id: 'snapshot-member-a',
    snapshotId: 'snapshot-1',
    personId: 'person-a',
    displayName: '김보영',
    groupId: 'group-1',
    groupName: '동준 상희 조',
    attendanceStatus: 'present',
    included: true,
  },
  {
    id: 'snapshot-member-b',
    snapshotId: 'snapshot-1',
    personId: 'person-b',
    displayName: '유성열',
    groupId: 'group-1',
    groupName: '동준 상희 조',
    attendanceStatus: 'late',
    included: true,
  },
  {
    id: 'snapshot-member-c',
    snapshotId: 'snapshot-1',
    personId: 'person-c',
    displayName: '과거구성원',
    groupId: 'group-1',
    groupName: '동준 상희 조',
    attendanceStatus: 'present',
    included: false,
  },
  {
    id: 'snapshot-member-d',
    snapshotId: 'snapshot-1',
    personId: 'person-d',
    displayName: '미편성',
    groupId: null,
    groupName: null,
    attendanceStatus: 'unknown',
    included: true,
  },
];

test('snapshot metrics use included members as the denominator', () => {
  const metrics = calculateSnapshotMetrics(members);

  assert.equal(metrics.totalPeople, 3);
  assert.equal(metrics.presentPeople, 2);
  assert.equal(metrics.absentPeople, 1);
  assert.equal(metrics.rate, 67);
});

test('excluded snapshot members never inflate attendance rate', () => {
  const metrics = calculateSnapshotMetrics([
    {
      id: 'snapshot-member-a',
      snapshotId: 'snapshot-1',
      personId: 'person-a',
      displayName: '제외된출석자',
      attendanceStatus: 'present',
      included: false,
    },
  ]);

  assert.equal(metrics.totalPeople, 0);
  assert.equal(metrics.presentPeople, 0);
  assert.equal(metrics.rate, null);
});

test('group display keeps excluded members visible but not counted', () => {
  const groups = groupSnapshotMembersForDisplay(members);
  const dongjunGroup = groups.find((group) => group.groupName === '동준 상희 조');
  const unassignedGroup = groups.find((group) => group.groupName === '미편성');

  assert.ok(dongjunGroup);
  assert.equal(dongjunGroup.totalPeople, 2);
  assert.equal(dongjunGroup.presentPeople, 2);
  assert.deepEqual(
    dongjunGroup.members.map((member) => member.displayName),
    ['과거구성원', '김보영', '유성열']
  );

  assert.ok(unassignedGroup);
  assert.equal(unassignedGroup.totalPeople, 1);
});

test('database rows are normalized for UI use', () => {
  const member = mapSnapshotMemberRow({
    id: 'snapshot-member-a',
    snapshot_id: 'snapshot-1',
    person_id: 'person-a',
    display_name: '상태없음',
    attendance_status: null,
    included: null,
  });

  assert.equal(member.attendanceStatus, 'unknown');
  assert.equal(member.included, true);
});
