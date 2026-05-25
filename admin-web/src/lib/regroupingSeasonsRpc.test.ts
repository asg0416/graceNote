import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyRegroupingSeason,
  createRegroupingSeason,
  registerCurrentRegroupingSeason,
  saveRegroupingSeasonDraft,
  syncCurrentRegroupingSeasonPlanFromLive,
  updateCurrentRegroupingGroupPeriods,
  updateRegroupingSeason,
} from './regroupingSeasonsRpc.ts';

const createRpcClient = (response: {
  data: unknown;
  error: { message?: string } | null;
}) => {
  const calls: Array<{ functionName: string; args?: Record<string, unknown> }> = [];

  return {
    calls,
    client: {
      rpc: async <T = unknown>(functionName: string, args?: Record<string, unknown>) => {
        calls.push({ functionName, args });
        return response as { data: T | null; error: { message?: string } | null };
      },
    },
  };
};

test('createRegroupingSeason sends the season creation payload', async () => {
  const { client, calls } = createRpcClient({ data: 'season-1', error: null });

  const result = await createRegroupingSeason(client, {
    churchId: 'church-1',
    departmentId: 'department-1',
    title: '2026년 3분기 조편성',
    effectiveWeekDate: '2026-07-05',
    endWeekDate: '2026-12-27',
  });

  assert.equal(result, 'season-1');
  assert.deepEqual(calls, [
    {
      functionName: 'create_regrouping_season',
      args: {
        p_church_id: 'church-1',
        p_department_id: 'department-1',
        p_title: '2026년 3분기 조편성',
        p_effective_week_date: '2026-07-05',
        p_end_week_date: '2026-12-27',
      },
    },
  ]);
});

test('saveRegroupingSeasonDraft returns normalized saved counts', async () => {
  const { client, calls } = createRpcClient({
    data: [{ plan_group_count: 2, assignment_count: 5 }],
    error: null,
  });

  const result = await saveRegroupingSeasonDraft(client, {
    seasonId: 'season-1',
    groups: [{ plan_group_id: 'group-1', name: 'A' }],
    assignments: [{ person_id: 'person-1', plan_group_id: 'group-1' }],
  });

  assert.deepEqual(result, { planGroupCount: 2, assignmentCount: 5 });
  assert.deepEqual(calls, [
    {
      functionName: 'save_regrouping_season_draft',
      args: {
        p_season_id: 'season-1',
        p_groups: [{ plan_group_id: 'group-1', name: 'A' }],
        p_assignments: [{ person_id: 'person-1', plan_group_id: 'group-1' }],
      },
    },
  ]);
});

test('registerCurrentRegroupingSeason sends the current live season registration payload', async () => {
  const { client, calls } = createRpcClient({ data: 'season-live-1', error: null });

  const result = await registerCurrentRegroupingSeason(client, {
    churchId: 'church-1',
    departmentId: 'department-1',
    title: '예닮부 현재 조편성',
    effectiveWeekDate: '2026-05-03',
    endWeekDate: '2026-06-28',
  });

  assert.equal(result, 'season-live-1');
  assert.deepEqual(calls, [
    {
      functionName: 'register_current_regrouping_season',
      args: {
        p_church_id: 'church-1',
        p_department_id: 'department-1',
        p_title: '예닮부 현재 조편성',
        p_effective_week_date: '2026-05-03',
        p_end_week_date: '2026-06-28',
      },
    },
  ]);
});

test('updateRegroupingSeason sends season metadata changes without live writes', async () => {
  const { client, calls } = createRpcClient({ data: null, error: null });

  await updateRegroupingSeason(client, {
    seasonId: 'season-1',
    title: '2026년 3분기 수정',
    effectiveWeekDate: '2026-07-12',
    endWeekDate: '2026-12-27',
  });

  assert.deepEqual(calls, [
    {
      functionName: 'update_regrouping_season',
      args: {
        p_season_id: 'season-1',
        p_title: '2026년 3분기 수정',
        p_effective_week_date: '2026-07-12',
        p_end_week_date: '2026-12-27',
      },
    },
  ]);
});

test('applyRegroupingSeason surfaces rpc errors', async () => {
  const { client } = createRpcClient({
    data: null,
    error: { message: 'season already applied' },
  });

  await assert.rejects(
    () => applyRegroupingSeason(client, { seasonId: 'season-1' }),
    /season already applied/
  );
});

test('syncCurrentRegroupingSeasonPlanFromLive returns normalized synced counts', async () => {
  const { client, calls } = createRpcClient({
    data: [{ plan_group_count: 3, assignment_count: 12 }],
    error: null,
  });

  const result = await syncCurrentRegroupingSeasonPlanFromLive(client, {
    seasonId: 'season-current',
  });

  assert.deepEqual(result, { planGroupCount: 3, assignmentCount: 12 });
  assert.deepEqual(calls, [
    {
      functionName: 'sync_current_regrouping_season_plan_from_live',
      args: {
        p_season_id: 'season-current',
      },
    },
  ]);
});

test('updateCurrentRegroupingGroupPeriods sends current season group period payload', async () => {
  const { client, calls } = createRpcClient({ data: 2, error: null });

  const result = await updateCurrentRegroupingGroupPeriods(client, {
    seasonId: 'season-current',
    groups: [
      {
        source_group_id: 'group-1',
        starts_week_date: '2026-01-04',
        ends_week_date: '2026-05-17',
        plan_status: 'ended',
      },
    ],
  });

  assert.equal(result, 2);
  assert.deepEqual(calls, [
    {
      functionName: 'update_current_regrouping_group_periods',
      args: {
        p_season_id: 'season-current',
        p_groups: [
          {
            source_group_id: 'group-1',
            starts_week_date: '2026-01-04',
            ends_week_date: '2026-05-17',
            plan_status: 'ended',
          },
        ],
      },
    },
  ]);
});
