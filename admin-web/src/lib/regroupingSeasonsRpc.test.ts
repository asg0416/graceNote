import assert from 'node:assert/strict';
import test from 'node:test';
import {
  applyRegroupingSeason,
  createRegroupingSeason,
  saveRegroupingSeasonDraft,
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

test('updateRegroupingSeason sends season metadata changes without live writes', async () => {
  const { client, calls } = createRpcClient({ data: null, error: null });

  await updateRegroupingSeason(client, {
    seasonId: 'season-1',
    title: '2026년 3분기 수정',
    effectiveWeekDate: '2026-07-12',
  });

  assert.deepEqual(calls, [
    {
      functionName: 'update_regrouping_season',
      args: {
        p_season_id: 'season-1',
        p_title: '2026년 3분기 수정',
        p_effective_week_date: '2026-07-12',
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
