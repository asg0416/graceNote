import assert from 'node:assert/strict';
import test from 'node:test';
import { applyBulkMemberPeriods, clampDateToRange } from './regroupingPeriodBulk.ts';

test('applyBulkMemberPeriods updates only selected member period fields', () => {
  const members = [
    { id: 'member-1', starts_week_date: '2026-01-04', ends_week_date: '2026-06-28', group_id: 'group-1' },
    { id: 'member-2', starts_week_date: '2026-02-01', ends_week_date: '2026-05-31', group_id: 'group-2' },
    { id: 'member-3', starts_week_date: '2026-03-01', ends_week_date: '2026-04-26', group_id: 'group-3' },
  ];

  assert.deepEqual(
    applyBulkMemberPeriods(members, ['member-1', 'member-3'], {
      starts_week_date: '2026-04-12',
      ends_week_date: '2026-05-24',
    }),
    [
      { id: 'member-1', starts_week_date: '2026-04-12', ends_week_date: '2026-05-24', group_id: 'group-1' },
      { id: 'member-2', starts_week_date: '2026-02-01', ends_week_date: '2026-05-31', group_id: 'group-2' },
      { id: 'member-3', starts_week_date: '2026-04-12', ends_week_date: '2026-05-24', group_id: 'group-3' },
    ]
  );
});

test('applyBulkMemberPeriods ignores empty period values', () => {
  const members = [
    { id: 'member-1', starts_week_date: '2026-01-04', ends_week_date: '2026-06-28' },
  ];

  assert.deepEqual(
    applyBulkMemberPeriods(members, ['member-1'], {
      starts_week_date: '',
      ends_week_date: '2026-05-24',
    }),
    [
      { id: 'member-1', starts_week_date: '2026-01-04', ends_week_date: '2026-05-24' },
    ]
  );
});

test('applyBulkMemberPeriods clamps each member to its own allowed range', () => {
  const members = [
    {
      id: 'member-1',
      starts_week_date: '2026-05-03',
      ends_week_date: '2026-05-31',
      recommended_starts_week_date: '2026-05-03',
      recommended_ends_week_date: '2026-05-31',
    },
    {
      id: 'member-2',
      starts_week_date: '2026-04-12',
      ends_week_date: '2026-06-28',
      recommended_starts_week_date: '2026-04-12',
      recommended_ends_week_date: '2026-06-28',
    },
  ];

  assert.deepEqual(
    applyBulkMemberPeriods(members, ['member-1', 'member-2'], {
      starts_week_date: '2026-04-01',
      ends_week_date: '2026-07-12',
    }),
    [
      {
        id: 'member-1',
        starts_week_date: '2026-05-03',
        ends_week_date: '2026-05-31',
        recommended_starts_week_date: '2026-05-03',
        recommended_ends_week_date: '2026-05-31',
      },
      {
        id: 'member-2',
        starts_week_date: '2026-04-12',
        ends_week_date: '2026-06-28',
        recommended_starts_week_date: '2026-04-12',
        recommended_ends_week_date: '2026-06-28',
      },
    ]
  );
});

test('clampDateToRange returns the nearest boundary when outside the range', () => {
  assert.equal(clampDateToRange('2026-04-01', '2026-05-03', '2026-06-28'), '2026-05-03');
  assert.equal(clampDateToRange('2026-07-05', '2026-05-03', '2026-06-28'), '2026-06-28');
  assert.equal(clampDateToRange('2026-05-24', '2026-05-03', '2026-06-28'), '2026-05-24');
});
