import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildSeasonPlanAttendanceRoster,
  type SeasonPlanAssignment,
  type SeasonPlanDirectoryMember,
  type SeasonPlanGroup,
} from './attendanceSeasonRoster.ts';

const planGroups: SeasonPlanGroup[] = [
  {
    id: 'plan-group-april',
    sourceGroupId: 'group-april',
    name: '4월생성테스트',
    startsWeekDate: '2026-04-05',
    endsWeekDate: '2026-04-26',
    planStatus: 'active',
  },
];

const assignments: SeasonPlanAssignment[] = [
  {
    id: 'assignment-young-eun',
    planGroupId: 'plan-group-april',
    personId: 'person-young-eun',
    sourceMemberDirectoryId: 'dir-young-eun',
    role: 'member',
    startsWeekDate: '2026-04-05',
    endsWeekDate: '2026-04-26',
  },
  {
    id: 'assignment-se-hyung',
    planGroupId: 'plan-group-april',
    personId: 'person-se-hyung',
    sourceMemberDirectoryId: 'dir-se-hyung',
    role: 'member',
    startsWeekDate: '2026-04-05',
    endsWeekDate: '2026-04-26',
  },
  {
    id: 'assignment-su-jin',
    planGroupId: 'plan-group-april',
    personId: 'person-su-jin',
    sourceMemberDirectoryId: 'dir-su-jin',
    role: 'leader',
    startsWeekDate: '2026-04-05',
    endsWeekDate: '2026-04-26',
  },
];

const directoryMembers: SeasonPlanDirectoryMember[] = [
  {
    id: 'dir-young-eun',
    full_name: '김영은',
    person_id: 'person-young-eun',
    starts_at: '2026-05-03',
    ends_at: '2026-07-04',
    is_active: true,
  },
  {
    id: 'dir-se-hyung',
    full_name: '이세형',
    person_id: 'person-se-hyung',
    starts_at: '2026-05-03',
    ends_at: '2026-07-04',
    is_active: true,
  },
  {
    id: 'dir-su-jin',
    full_name: '이수진',
    person_id: 'person-su-jin',
    starts_at: '2026-04-05',
    ends_at: '2026-05-02',
    is_active: true,
  },
];

test('season plan roster uses plan assignment dates instead of live membership dates', () => {
  const roster = buildSeasonPlanAttendanceRoster({
    weekDate: '2026-04-12',
    planGroups,
    assignments,
    directoryMembers,
  });

  assert.deepEqual(
    roster.map((member) => [member.full_name, member.group_name, member.role_in_group]),
    [
      ['김영은', '4월생성테스트', 'member'],
      ['이세형', '4월생성테스트', 'member'],
      ['이수진', '4월생성테스트', 'leader'],
    ]
  );
  assert.deepEqual(
    roster.map((member) => [member.starts_at, member.ends_at]),
    [
      ['2026-04-05', '2026-04-26'],
      ['2026-04-05', '2026-04-26'],
      ['2026-04-05', '2026-04-26'],
    ]
  );
});

test('season plan roster excludes groups outside the selected week', () => {
  const roster = buildSeasonPlanAttendanceRoster({
    weekDate: '2026-06-21',
    planGroups,
    assignments,
    directoryMembers,
  });

  assert.deepEqual(roster, []);
});

