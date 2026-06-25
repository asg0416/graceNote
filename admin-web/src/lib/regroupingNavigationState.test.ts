import assert from 'node:assert/strict';
import test from 'node:test';
import { shouldReturnToSeasonListOnMissingSeasonQuery } from './regroupingNavigationState.ts';

test('does not treat a just-saved season URL sync as browser back navigation', () => {
  assert.equal(
    shouldReturnToSeasonListOnMissingSeasonQuery({
      seasonIdFromQuery: null,
      selectedSeasonId: 'season-1',
      regroupingView: 'seasonEditor',
      pendingSeasonUrlSyncId: 'season-1',
    }),
    false,
  );
});

test('treats missing season query for an open saved season as list back navigation', () => {
  assert.equal(
    shouldReturnToSeasonListOnMissingSeasonQuery({
      seasonIdFromQuery: null,
      selectedSeasonId: 'season-1',
      regroupingView: 'seasonEditor',
      pendingSeasonUrlSyncId: null,
    }),
    true,
  );
});
