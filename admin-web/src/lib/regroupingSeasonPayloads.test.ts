import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildRegroupingSeasonAssignmentsPayload,
  buildRegroupingSeasonGroupsPayload,
  mapRegroupingSeasonDraftToBoard,
  mergeAppliedSeasonMemberWithLiveMembership,
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
        change_type: null,
        previous_source_group_id: null,
        previous_group_name: null,
        source_membership_id: '44444444-4444-4444-8444-444444444444',
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        starts_week_date: '2026-07-12',
        ends_week_date: '2026-11-29',
      },
    ]
  );
});

test('buildRegroupingSeasonAssignmentsPayload keeps directory id for live membership cards', () => {
  assert.deepEqual(
    buildRegroupingSeasonAssignmentsPayload([
      {
        id: 'live-membership-44444444-4444-4444-8444-444444444444',
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        group_id: '11111111-1111-4111-8111-111111111111',
        phase2_person_id: '33333333-3333-4333-8333-333333333333',
        phase2_membership_id: '44444444-4444-4444-8444-444444444444',
        role_in_group: 'leader',
        starts_week_date: '2026-07-05',
        ends_week_date: '2026-11-29',
      },
    ]),
    [
      {
        group_id: '11111111-1111-4111-8111-111111111111',
        plan_group_id: null,
        person_id: '33333333-3333-4333-8333-333333333333',
        role_in_group: 'leader',
        sort_order: 0,
        change_type: null,
        previous_source_group_id: null,
        previous_group_name: null,
        source_membership_id: '44444444-4444-4444-8444-444444444444',
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        starts_week_date: '2026-07-05',
        ends_week_date: '2026-11-29',
      },
    ]
  );
});

test('buildRegroupingSeasonAssignmentsPayload keeps removed source membership rows', () => {
  assert.deepEqual(
    buildRegroupingSeasonAssignmentsPayload([
      {
        id: '22222222-2222-4222-8222-222222222222',
        group_id: null,
        phase2_person_id: '33333333-3333-4333-8333-333333333333',
        phase2_membership_id: '44444444-4444-4444-8444-444444444444',
        plan_change_type: 'removed',
        previous_source_group_id: '66666666-6666-4666-8666-666666666666',
        previous_group_name: '효석 해비 조',
        role_in_group: 'member',
        starts_week_date: '2026-01-04',
        ends_week_date: '2026-05-31',
      },
    ]),
    [
      {
        group_id: null,
        plan_group_id: null,
        person_id: '33333333-3333-4333-8333-333333333333',
        role_in_group: 'member',
        sort_order: 0,
        change_type: 'removed',
        previous_source_group_id: '66666666-6666-4666-8666-666666666666',
        previous_group_name: '효석 해비 조',
        source_membership_id: '44444444-4444-4444-8444-444444444444',
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        starts_week_date: '2026-01-04',
        ends_week_date: '2026-05-31',
      },
    ]
  );
});

test('buildRegroupingSeasonAssignmentsPayload does not store stale added label for removed rows', () => {
  const result = buildRegroupingSeasonAssignmentsPayload([
    {
      id: '22222222-2222-4222-8222-222222222222',
      group_id: null,
      phase2_person_id: '33333333-3333-4333-8333-333333333333',
      phase2_membership_id: '44444444-4444-4444-8444-444444444444',
      plan_change_type: 'removed',
      previous_source_group_id: '66666666-6666-4666-8666-666666666666',
      previous_group_name: '추가 소속',
      source_membership_group_name: '귀동 선경 조',
      role_in_group: 'member',
    },
  ]);

  assert.equal(result[0].previous_group_name, '귀동 선경 조');
});

test('buildRegroupingSeasonAssignmentsPayload keeps removed history and unassigned department rows separately', () => {
  assert.deepEqual(
    buildRegroupingSeasonAssignmentsPayload([
      {
        id: '22222222-2222-4222-8222-222222222222',
        group_id: null,
        phase2_person_id: '33333333-3333-4333-8333-333333333333',
        phase2_membership_id: '44444444-4444-4444-8444-444444444444',
        plan_change_type: 'removed',
        previous_source_group_id: '66666666-6666-4666-8666-666666666666',
        previous_group_name: '기존 조',
        role_in_group: 'member',
        starts_week_date: '2026-01-04',
        ends_week_date: '2026-05-17',
      },
      {
        id: 'temp-unassigned-1',
        group_id: null,
        phase2_person_id: '33333333-3333-4333-8333-333333333333',
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        role_in_group: 'member',
        starts_week_date: '2026-05-24',
        ends_week_date: '2026-06-28',
      },
    ]),
    [
      {
        group_id: null,
        plan_group_id: null,
        person_id: '33333333-3333-4333-8333-333333333333',
        role_in_group: 'member',
        sort_order: 0,
        change_type: 'removed',
        previous_source_group_id: '66666666-6666-4666-8666-666666666666',
        previous_group_name: '기존 조',
        source_membership_id: '44444444-4444-4444-8444-444444444444',
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        starts_week_date: '2026-01-04',
        ends_week_date: '2026-05-17',
      },
      {
        group_id: null,
        plan_group_id: null,
        person_id: '33333333-3333-4333-8333-333333333333',
        role_in_group: 'member',
        sort_order: 1,
        change_type: null,
        previous_source_group_id: null,
        previous_group_name: null,
        source_membership_id: null,
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        starts_week_date: '2026-05-24',
        ends_week_date: '2026-06-28',
      },
    ]
  );
});

test('buildRegroupingSeasonAssignmentsPayload does not persist previous source group for added copies', () => {
  assert.deepEqual(
    buildRegroupingSeasonAssignmentsPayload([
      {
        id: 'temp-copy-1',
        group_id: '77777777-7777-4777-8777-777777777777',
        phase2_person_id: '33333333-3333-4333-8333-333333333333',
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        source_membership_group_id: '77777777-7777-4777-8777-777777777777',
        source_membership_group_name: '동준 상희 조',
        plan_change_type: 'added',
        previous_group_name: '추가 소속',
        previous_source_group_id: '77777777-7777-4777-8777-777777777777',
        role_in_group: 'member',
        starts_week_date: '2026-05-03',
        ends_week_date: '2026-06-28',
      },
    ]),
    [
      {
        group_id: '77777777-7777-4777-8777-777777777777',
        plan_group_id: null,
        person_id: '33333333-3333-4333-8333-333333333333',
        role_in_group: 'member',
        sort_order: 0,
        change_type: 'added',
        previous_source_group_id: null,
        previous_group_name: '추가 소속',
        source_membership_id: null,
        source_member_directory_id: '22222222-2222-4222-8222-222222222222',
        starts_week_date: '2026-05-03',
        ends_week_date: '2026-06-28',
      },
    ],
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
      is_active: true,
      left_at: null,
      person_id: '99999999-9999-4999-8999-999999999999',
      phase2_person_id: '99999999-9999-4999-8999-999999999999',
      phase2_membership_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      plan_change_type: null,
      previous_source_group_id: null,
      previous_group_name: null,
      source_membership_group_id: null,
      source_membership_group_name: null,
      source_member_directory_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      starts_week_date: '2026-07-05',
      ends_week_date: '2026-12-27',
    },
  ]);
});

test('mapRegroupingSeasonDraftToBoard restores added copy family fields and target group metadata', () => {
  const result = mapRegroupingSeasonDraftToBoard({
    planGroups: [],
    assignments: [
      {
        id: '88888888-8888-4888-8888-888888888887',
        plan_group_id: '77777777-7777-4777-8777-777777777777',
        person_id: '99999999-9999-4999-8999-999999999999',
        role_in_group: 'member',
        sort_order: 1,
        change_type: 'added',
        previous_source_group_id: '77777777-7777-4777-8777-777777777777',
        previous_source_group: { name: '동준 상희 조' },
        previous_group_name: '추가 소속',
        source_member_directory_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        people: { display_name: '김지유' },
        member_directory: {
          full_name: '김지유',
          phone: '01011112222',
          spouse_name: '배우자',
          family_name: '김',
        },
      },
    ],
  });

  assert.equal(result.members[0].full_name, '김지유');
  assert.equal(result.members[0].spouse_name, '배우자');
  assert.equal(result.members[0].family_name, '김');
  assert.equal(result.members[0].plan_change_type, 'added');
  assert.equal(result.members[0].previous_source_group_id, '77777777-7777-4777-8777-777777777777');
  assert.equal(result.members[0].source_membership_group_name, '동준 상희 조');
  assert.equal(result.members[0].source_member_directory_id, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
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

test('mapRegroupingSeasonDraftToBoard restores removed assignment group name from member directory', () => {
  const result = mapRegroupingSeasonDraftToBoard({
    planGroups: [],
    assignments: [
      {
        id: '88888888-8888-4888-8888-888888888883',
        plan_group_id: null,
        person_id: '99999999-9999-4999-8999-999999999999',
        role_in_group: 'member',
        sort_order: 1,
        source_membership_id: null,
        source_member_directory_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        change_type: 'removed',
        previous_source_group_id: '66666666-6666-4666-8666-666666666666',
        previous_group_name: '효석 해비 조',
        starts_week_date: '2026-01-04',
        ends_week_date: '2026-05-31',
        people: { display_name: '이종료' },
        member_directory: {
          full_name: '이종료',
          phone: '01011112222',
          group_name: '효석 해비 조',
        },
      },
    ],
  });

  assert.equal(result.members[0].group_id, null);
  assert.equal(result.members[0].plan_change_type, 'removed');
  assert.equal(result.members[0].previous_source_group_id, '66666666-6666-4666-8666-666666666666');
  assert.equal(result.members[0].previous_group_name, '효석 해비 조');
  assert.equal(result.members[0].source_membership_group_id, '66666666-6666-4666-8666-666666666666');
  assert.equal(result.members[0].source_membership_group_name, '효석 해비 조');
});

test('mapRegroupingSeasonDraftToBoard restores legacy member directory id from source membership', () => {
  const result = mapRegroupingSeasonDraftToBoard({
    planGroups: [],
    assignments: [
      {
        id: '88888888-8888-4888-8888-888888888884',
        plan_group_id: null,
        person_id: '99999999-9999-4999-8999-999999999999',
        role_in_group: 'member',
        sort_order: 1,
        source_membership_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        source_member_directory_id: null,
        change_type: 'removed',
        previous_group_name: '기존 조',
        people: { display_name: '김미편성' },
        source_membership: {
          group_id: '66666666-6666-4666-8666-666666666666',
          legacy_member_directory_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          group: { name: '기존 조' },
        },
      },
    ],
  });

  assert.equal(result.members[0].source_member_directory_id, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  assert.equal(result.members[0].source_membership_group_id, '66666666-6666-4666-8666-666666666666');
  assert.equal(result.members[0].source_membership_group_name, '기존 조');
});

test('mapRegroupingSeasonDraftToBoard prefers source membership group over stale added label', () => {
  const result = mapRegroupingSeasonDraftToBoard({
    planGroups: [],
    assignments: [
      {
        id: '88888888-8888-4888-8888-888888888885',
        plan_group_id: null,
        person_id: '99999999-9999-4999-8999-999999999999',
        role_in_group: 'member',
        sort_order: 1,
        source_membership_id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaab',
        source_member_directory_id: null,
        change_type: 'removed',
        previous_group_name: '추가 소속',
        people: { display_name: '이종료' },
        source_membership: {
          group_id: '66666666-6666-4666-8666-666666666666',
          legacy_member_directory_id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          group: { name: '효석 해비 조' },
        },
      },
    ],
  });

  assert.equal(result.members[0].previous_group_name, '추가 소속');
  assert.equal(result.members[0].source_membership_group_name, '효석 해비 조');
});

test('mapRegroupingSeasonDraftToBoard restores removed group name from previous source group', () => {
  const result = mapRegroupingSeasonDraftToBoard({
    planGroups: [],
    assignments: [
      {
        id: '88888888-8888-4888-8888-888888888886',
        plan_group_id: null,
        person_id: '99999999-9999-4999-8999-999999999999',
        role_in_group: 'member',
        sort_order: 1,
        source_membership_id: null,
        source_member_directory_id: null,
        change_type: 'removed',
        previous_source_group_id: '66666666-6666-4666-8666-666666666666',
        previous_group_name: null,
        people: { display_name: '이종료' },
        previous_source_group: { name: '귀동 선경 조' },
      },
    ],
  });

  assert.equal(result.members[0].source_membership_group_name, '귀동 선경 조');
});

test('mergeAppliedSeasonMemberWithLiveMembership clears historical apply markers', () => {
  const result = mergeAppliedSeasonMemberWithLiveMembership(
    {
      id: 'season-assignment-1',
      group_id: 'plan-group-1',
      full_name: '김적용',
      plan_change_type: 'added',
      change_type: 'added',
      previous_group_name: '추가 소속',
      previous_source_group_id: 'old-plan-group',
      phase2_membership_id: null,
      source_membership_group_id: null,
      source_membership_group_name: null,
      starts_week_date: '2026-07-05',
      ends_week_date: '2026-11-29',
    },
    {
      group_id: 'plan-group-1',
      group_name: '현권 영미 조',
      phase2_membership_id: 'membership-1',
      source_membership_group_id: 'live-group-1',
      source_membership_group_name: '현권 영미 조',
      starts_week_date: '2026-07-05',
      ends_week_date: '2026-11-29',
    },
  );

  assert.equal(result.plan_change_type, null);
  assert.equal(result.change_type, null);
  assert.equal(result.previous_group_name, null);
  assert.equal(result.previous_source_group_id, null);
  assert.equal(result.phase2_membership_id, 'membership-1');
  assert.equal(result.source_membership_group_id, 'live-group-1');
  assert.equal(result.source_membership_group_name, '현권 영미 조');
});

test('mergeAppliedSeasonMemberWithLiveMembership keeps applied season period over stale live period', () => {
  const result = mergeAppliedSeasonMemberWithLiveMembership(
    {
      id: 'season-assignment-1',
      group_id: 'plan-group-1',
      full_name: '김적용',
      starts_week_date: '2026-07-05',
      ends_week_date: '2026-11-29',
    },
    {
      group_id: 'plan-group-1',
      starts_week_date: '2026-06-28',
      ends_week_date: '2026-11-29',
    },
  );

  assert.equal(result.starts_week_date, '2026-07-05');
  assert.equal(result.ends_week_date, '2026-11-29');
});
