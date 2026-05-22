import assert from 'node:assert/strict';
import test from 'node:test';
import { localGates } from './preprod-local-gates.mjs';

test('preprod local gates include regrouping season boundary guard', () => {
  assert.deepEqual(
    localGates.some(gate => gate.name === 'regrouping season boundary'),
    true
  );
});
