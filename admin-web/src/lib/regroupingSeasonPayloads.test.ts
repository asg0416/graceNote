import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildRegroupingSeasonAssignmentsPayload,
  buildRegroupingSeasonGroupsPayload,
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
