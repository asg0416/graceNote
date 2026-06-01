import test from 'node:test';
import assert from 'node:assert/strict';
import { isPeriodEdited } from './periodBadgeState.ts';

test('isPeriodEdited returns false when period stays the same', () => {
    assert.equal(isPeriodEdited('2026-01-04', '2026-06-28', '2026-01-04', '2026-06-28'), false);
});

test('isPeriodEdited returns true when start or end changes', () => {
    assert.equal(isPeriodEdited('2026-01-04', '2026-06-28', '2026-02-01', '2026-06-28'), true);
    assert.equal(isPeriodEdited('2026-01-04', '2026-06-28', '2026-01-04', '2026-05-31'), true);
});

test('isPeriodEdited treats undefined and null as the same empty value', () => {
    assert.equal(isPeriodEdited(undefined, null, null, undefined), false);
});
