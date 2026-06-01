import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildRegroupingSeasonAssignmentsPayload,
  buildRegroupingSeasonGroupsPayload,
  mapRegroupingSeasonDraftToBoard,
} from './regroupingSeasonPayloads.ts';

test('buildRegroupingSeasonGroupsPayload keeps client id and separates source group id', () => {
  const existingGroupId = '11111111-1111-4111-8111-111111111111';
  const planGroupId = '55555555-5555-4555-8555-555555555555';

  assert.deepEqual(
    buildRegroupingSeasonGroupsPayload([
      { id: existingGroupId, name: '기존 조', color_hex: '#123456', starts_week_date: '2026-07-05' },
      { id: planGroupId, plan_group_id: planGroupId, name: '초안 신규 조', color_hex: '#abcdef', ends_week_date: '2026-12-27', plan_status: 'ended', is_new_member_group: true, climbing_threshold: 5 },
      { id: 'temp-1', name: '신규 조', color_hex: '#654321' },
    ]),
    [
      {
        id: existingGroupId,
        plan_group_id: null,
        source_group_id: existingGroupId,
        name: '기존 조',
        color_hex: '#123456',
        sort_order: 0,
        leader_person_id: null,
        starts_week_date: '2026-07-05',
        ends_week_date: null,
        plan_status: 'active',
        is_new_member_group: false,
        climbing_threshold: null,
      },
      {
        id: planGroupId,
        plan_group_id: planGroupId,
        source_group_id: null,
        name: '초안 신규 조',
        color_hex: '#abcdef',
        sort_order: 1,
        leader_person_id: null,
        starts_week_date: null,
        ends_week_date: '2026-12-27',
        plan_status: 'ended',
        is_new_member_group: true,
        climbing_threshold: 5,
      },
      {
        id: 'temp-1',
        plan_group_id: null,
        source_group_id: null,
        name: '신규 조',
        color_hex: '#654321',
        sort_order: 2,
        leader_person_id: null,
        starts_week_date: null,
        ends_week_date: null,
        plan_status: 'active',
        is_new_member_group: false,
        climbing_threshold: null,
      },
    ]
  );
});

test('buildRegroupingSeasonAssignmentsPayload maps temp group ids and phase2 ids', () => {
  assert.deepEqual(
    buildRegroupingSeasonAssignmentsPayload([
      {
        id: '22222222-2222-4222-8222-222222222222',
        group_id: 'temp-1',
        phase2_person_id: '33333333-3333-4333-8333-333333333333',
        phase2_membership_id: '44444444-4444-4444-8444-444444444444',
        role_in_group: 'leader',
        starts_week_date: '2026-07-12',
        ends_week_date: '2026-11-29',
      },
      {
        id: 'temp-new',
        group_id: null,
        person_id: null,
      },
    ]),
    [
      {
        group_id: 'temp-1',
        plan_group_id: null,
        person_id: '33333333-3333-4333-8333-333333333333',
        role_in_group: 'leader',
        sort_order: 0,
        source_membership_id: '44444444-4444-4444-8444-444444444444',
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        starts_week_date: '2026-07-12',
        ends_week_date: '2026-11-29',
      },
    ]
  );
});

test('mapRegroupingSeasonDraftToBoard restores plan groups and assignments for kanban', () => {
  const result = mapRegroupingSeasonDraftToBoard({
    planGroups: [
      {
        id: '55555555-5555-4555-8555-555555555555',
        source_group_id: '66666666-6666-4666-8666-666666666666',
        name: '기존 조',
        color_hex: '#111111',
        sort_order: 1,
        starts_week_date: '2026-01-04',
        ends_week_date: '2026-06-28',
        plan_status: 'active',
        source_group: { is_new_member_group: true, climbing_threshold: 3 },
      },
      {
        id: '77777777-7777-4777-8777-777777777777',
        source_group_id: null,
        name: '신규 조',
        color_hex: '#222222',
        sort_order: 2,
        starts_week_date: '2026-07-05',
        ends_week_date: null,
        plan_status: 'ended',
      },
    ],
    assignments: [
      {
        id: '88888888-8888-4888-8888-888888888888',
        plan_group_id: '77777777-7777-4777-8777-777777777777',
        person_id: '99999999-9999-4999-8999-999999999999',
        role_in_group: 'leader',
        sort_order: 3,
        source_membership_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        source_member_directory_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        starts_week_date: '2026-07-05',
        ends_week_date: '2026-12-27',
        people: { display_name: '김시즌', normalized_phone: '01011112222' },
        member_directory: {
          full_name: '김레거시',
          phone: '01033334444',
          family_name: '김',
          spouse_name: '이배우',
          children_info: '자녀 1',
          birth_date: '1990-01-01',
          wedding_anniversary: '2015-05-05',
          notes: '메모',
          avatar_url: 'https://example.test/avatar.png',
          profile_id: 'profile-1',
        },
      },
    ],
  });

  assert.deepEqual(result.groups, [
    {
      id: '55555555-5555-4555-8555-555555555555',
      plan_group_id: '55555555-5555-4555-8555-555555555555',
      source_group_id: '66666666-6666-4666-8666-666666666666',
      name: '기존 조',
      color_hex: '#111111',
      sort_order: 1,
      starts_week_date: '2026-01-04',
      ends_week_date: '2026-06-28',
      plan_status: 'active',
      is_new_member_group: true,
      climbing_threshold: 3,
    },
    {
      id: '77777777-7777-4777-8777-777777777777',
      plan_group_id: '77777777-7777-4777-8777-777777777777',
      source_group_id: null,
      name: '신규 조',
      color_hex: '#222222',
      sort_order: 2,
      starts_week_date: '2026-07-05',
      ends_week_date: null,
      plan_status: 'ended',
      is_new_member_group: false,
      climbing_threshold: null,
    },
  ]);
  assert.deepEqual(result.members, [
    {
      id: 'season-88888888-8888-4888-8888-888888888888',
      season_assignment_id: '88888888-8888-4888-8888-888888888888',
      full_name: '김레거시',
      phone: '01033334444',
      group_id: '77777777-7777-4777-8777-777777777777',
      role_in_group: 'leader',
      family_name: '김',
      spouse_name: '이배우',
      children_info: '자녀 1',
      birth_date: '1990-01-01',
      wedding_anniversary: '2015-05-05',
      notes: '메모',
      avatar_url: 'https://example.test/avatar.png',
      profile_id: 'profile-1',
      person_id: '99999999-9999-4999-8999-999999999999',
      phase2_person_id: '99999999-9999-4999-8999-999999999999',
      phase2_membership_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      source_membership_group_id: null,
      source_membership_group_name: null,
      source_member_directory_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      starts_week_date: '2026-07-05',
      ends_week_date: '2026-12-27',
    },
  ]);
});

test('mapRegroupingSeasonDraftToBoard keeps duplicate person assignments as separate cards', () => {
  const sourceDirectoryId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

  const result = mapRegroupingSeasonDraftToBoard({
    planGroups: [],
    assignments: [
      {
        id: '88888888-8888-4888-8888-888888888881',
        plan_group_id: '77777777-7777-4777-8777-777777777771',
        person_id: '99999999-9999-4999-8999-999999999999',
        role_in_group: 'member',
        sort_order: 1,
        source_member_directory_id: sourceDirectoryId,
        people: { display_name: '이다중' },
      },
      {
        id: '88888888-8888-4888-8888-888888888882',
        plan_group_id: '77777777-7777-4777-8777-777777777772',
        person_id: '99999999-9999-4999-8999-999999999999',
        role_in_group: 'leader',
        sort_order: 2,
        source_member_directory_id: sourceDirectoryId,
        people: { display_name: '이다중' },
      },
    ],
  });

  assert.deepEqual(
    result.members.map(member => ({
      id: member.id,
      source_member_directory_id: member.source_member_directory_id,
      group_id: member.group_id,
      role_in_group: member.role_in_group,
    })),
    [
      {
        id: 'season-88888888-8888-4888-8888-888888888881',
        source_member_directory_id: sourceDirectoryId,
        group_id: '77777777-7777-4777-8777-777777777771',
        role_in_group: 'member',
      },
      {
        id: 'season-88888888-8888-4888-8888-888888888882',
        source_member_directory_id: sourceDirectoryId,
        group_id: '77777777-7777-4777-8777-777777777772',
        role_in_group: 'leader',
      },
    ],
  );
});
