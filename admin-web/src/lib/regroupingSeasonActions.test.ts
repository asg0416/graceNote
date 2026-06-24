import assert from 'node:assert/strict';
import test from 'node:test';
import {
  canApplyRegroupingSeason,
  canDeletePendingRegroupingSeason,
} from './regroupingSeasonActions.ts';

test('allows deleting draft seasons even after the effective week has arrived', () => {
  assert.equal(
    canDeletePendingRegroupingSeason({
      status: 'draft',
      effective_week_date: '2026-06-21',
    }),
    true,
  );
});

test('allows deleting ready seasons until they are applied', () => {
  assert.equal(
    canDeletePendingRegroupingSeason({
      status: 'ready',
      effective_week_date: '2026-06-21',
    }),
    true,
  );
});

test('does not allow deleting applied seasons', () => {
  assert.equal(
    canDeletePendingRegroupingSeason({
      status: 'applied',
      effective_week_date: '2026-06-21',
    }),
    false,
  );
});

test('does not allow applying a season while screen changes are unsaved', () => {
  assert.equal(
    canApplyRegroupingSeason({
      mode: 'season',
      hasSelectedSeason: true,
      isApplied: false,
      isFuture: false,
      hasInvalidPeriod: false,
      hasOverlappingPeriod: false,
      hasUnsavedChanges: true,
    }),
    false,
  );
});

test('allows applying a saved due season draft', () => {
  assert.equal(
    canApplyRegroupingSeason({
      mode: 'season',
      hasSelectedSeason: true,
      isApplied: false,
      isFuture: false,
      hasInvalidPeriod: false,
      hasOverlappingPeriod: false,
      hasUnsavedChanges: false,
    }),
    true,
  );
});
