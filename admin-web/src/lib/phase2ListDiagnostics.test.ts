import assert from 'node:assert/strict';
import test from 'node:test';
import { buildCurrentSeasonPhase2ListCheck } from './phase2ListDiagnostics.ts';

test('current season diagnostics ignore members intentionally left unassigned', () => {
  const result = buildCurrentSeasonPhase2ListCheck({
    activeLegacyMembers: [
      { id: 'directory-1', phase2PersonId: 'person-1', personKey: 'person-1' },
      { id: 'directory-2', phase2PersonId: 'person-2', personKey: 'person-2' },
    ],
    planAssignments: [
      { personId: 'person-1' },
      { personId: 'person-2' },
    ],
  });

  assert.equal(result.issueCount, 0);
  assert.equal(result.missingCount, 0);
  assert.equal(result.extraCount, 0);
  assert.equal(result.phase2ActiveCount, 2);
  assert.equal(result.phase2ActivePersonCount, 2);
});

test('current season diagnostics still report assigned members missing from the season plan', () => {
  const result = buildCurrentSeasonPhase2ListCheck({
    activeLegacyMembers: [
      { id: 'directory-1', phase2PersonId: 'person-1', personKey: 'person-1' },
      { id: 'directory-2', phase2PersonId: 'person-2', personKey: 'person-2' },
    ],
    planAssignments: [
      { personId: 'person-1' },
    ],
  });

  assert.equal(result.issueCount, 1);
  assert.equal(result.missingCount, 1);
  assert.equal(result.extraCount, 0);
  assert.equal(result.phase2ActiveCount, 1);
  assert.equal(result.phase2ActivePersonCount, 1);
});
