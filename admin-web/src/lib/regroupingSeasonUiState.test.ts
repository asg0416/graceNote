import assert from 'node:assert/strict';
import test from 'node:test';
import { isRegroupingBoardReadonly, shouldShowSeasonMemberPeriodChange } from './regroupingSeasonUiState.ts';

test('applied season boards are read-only', () => {
  assert.equal(isRegroupingBoardReadonly('season', 'applied'), true);
});

test('draft and ready season boards remain editable', () => {
  assert.equal(isRegroupingBoardReadonly('season', 'draft'), false);
  assert.equal(isRegroupingBoardReadonly('season', 'ready'), false);
});

test('live correction boards remain editable regardless of season status', () => {
  assert.equal(isRegroupingBoardReadonly('live', 'applied'), false);
  assert.equal(isRegroupingBoardReadonly('live', null), false);
});

test('period change remains visible after user corrects the current value until save resets baseline', () => {
  assert.equal(
    shouldShowSeasonMemberPeriodChange({
      currentStart: '2026-02-01',
      currentEnd: '2026-06-28',
      expectedStart: '2026-02-01',
      expectedEnd: '2026-06-28',
      baselineStart: '2026-01-04',
      baselineEnd: '2026-06-28',
    }),
    true
  );
});

test('period change is hidden only when current and baseline both match expected range', () => {
  assert.equal(
    shouldShowSeasonMemberPeriodChange({
      currentStart: '2026-02-01',
      currentEnd: '2026-06-28',
      expectedStart: '2026-02-01',
      expectedEnd: '2026-06-28',
      baselineStart: '2026-02-01',
      baselineEnd: '2026-06-28',
    }),
    false
  );
});
