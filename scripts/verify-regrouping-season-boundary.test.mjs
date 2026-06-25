import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import test from 'node:test';
import { findRegroupingSeasonBoundaryViolations } from './verify-regrouping-season-boundary.mjs';

test('allows regrouping season draft references inside regrouping admin code', async () => {
  const root = await mkdtemp(join(tmpdir(), 'regrouping-boundary-'));
  try {
    await mkdir(join(root, 'admin-web/src/app/regrouping'), { recursive: true });
    await writeFile(
      join(root, 'admin-web/src/app/regrouping/page.tsx'),
      "supabase.from('regrouping_seasons').select('*');"
    );

    const violations = await findRegroupingSeasonBoundaryViolations(root);
    assert.deepEqual(violations, []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('allows applied season plan reads in operational app code', async () => {
  const root = await mkdtemp(join(tmpdir(), 'regrouping-boundary-'));
  try {
    await mkdir(join(root, 'lib/features/prayer'), { recursive: true });
    await writeFile(
      join(root, 'lib/features/prayer/prayer_repository.dart'),
      "client.from('regrouping_seasons').select('*').eq('status', 'applied');"
    );
    await writeFile(
      join(root, 'lib/features/prayer/season_roster.dart'),
      "final table = 'regrouping_plan_assignments';"
    );

    const violations = await findRegroupingSeasonBoundaryViolations(root);
    assert.deepEqual(violations, []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('allows model files to define draft status values', async () => {
  const root = await mkdtemp(join(tmpdir(), 'regrouping-boundary-'));
  try {
    await mkdir(join(root, 'lib/core/models'), { recursive: true });
    await writeFile(
      join(root, 'lib/core/models/models.dart'),
      "class Notice { final String status; Notice({this.status = 'draft'}); }"
    );

    const violations = await findRegroupingSeasonBoundaryViolations(root);
    assert.deepEqual(violations, []);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('blocks regrouping season draft write APIs in operational app code', async () => {
  const root = await mkdtemp(join(tmpdir(), 'regrouping-boundary-'));
  try {
    await mkdir(join(root, 'lib/features/prayer'), { recursive: true });
    await writeFile(
      join(root, 'lib/features/prayer/prayer_repository.dart'),
      "await client.rpc('save_regrouping_season_draft');"
    );

    const violations = await findRegroupingSeasonBoundaryViolations(root);
    assert.equal(violations.length, 1);
    assert.match(violations[0], /lib\/features\/prayer\/prayer_repository\.dart/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('blocks explicit draft status reads in operational app code', async () => {
  const root = await mkdtemp(join(tmpdir(), 'regrouping-boundary-'));
  try {
    await mkdir(join(root, 'lib/features/prayer'), { recursive: true });
    await writeFile(
      join(root, 'lib/features/prayer/prayer_repository.dart'),
      "client.from('regrouping_seasons').select('*').eq('status', 'draft');"
    );

    const violations = await findRegroupingSeasonBoundaryViolations(root);
    assert.equal(violations.length, 1);
    assert.match(violations[0], /lib\/features\/prayer\/prayer_repository\.dart/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
