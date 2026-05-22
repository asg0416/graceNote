import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildRegroupingSeasonAssignmentsPayload,
  buildRegroupingSeasonGroupsPayload,
  mapRegroupingSeasonDraftToBoard,
} from './regroupingSeasonPayloads.ts';

test('buildRegroupingSeasonGroupsPayload keeps client id and separates source group id', () => {
  const existingGroupId = '11111111-1111-4111-8111-111111111111';

  assert.deepEqual(
    buildRegroupingSeasonGroupsPayload([
      { id: existingGroupId, name: '기존 조', color_hex: '#123456' },
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
      },
      {
        id: 'temp-1',
        plan_group_id: null,
        source_group_id: null,
        name: '신규 조',
        color_hex: '#654321',
        sort_order: 1,
        leader_person_id: null,
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
      },
      {
        id: '77777777-7777-4777-8777-777777777777',
        source_group_id: null,
        name: '신규 조',
        color_hex: '#222222',
        sort_order: 2,
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
        people: { display_name: '김시즌', normalized_phone: '01011112222' },
        member_directory: { full_name: '김레거시', phone: '01033334444' },
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
    },
    {
      id: '77777777-7777-4777-8777-777777777777',
      plan_group_id: '77777777-7777-4777-8777-777777777777',
      source_group_id: null,
      name: '신규 조',
      color_hex: '#222222',
      sort_order: 2,
    },
  ]);
  assert.deepEqual(result.members, [
    {
      id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      season_assignment_id: '88888888-8888-4888-8888-888888888888',
      full_name: '김레거시',
      phone: '01033334444',
      group_id: '77777777-7777-4777-8777-777777777777',
      role_in_group: 'leader',
      person_id: '99999999-9999-4999-8999-999999999999',
      phase2_person_id: '99999999-9999-4999-8999-999999999999',
      phase2_membership_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      source_member_directory_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    },
  ]);
});
