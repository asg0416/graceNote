import assert from 'node:assert/strict';
import test from 'node:test';
import { isRegroupingBoardReadonly } from './regroupingSeasonUiState.ts';

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
