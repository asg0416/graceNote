import assert from 'node:assert/strict';
import test from 'node:test';
import {
  buildAdminOAuthRedirectTo,
  decideAdminAuthRedirect,
  normalizeAdminNextPath,
} from './adminAuth.ts';

test('social auth redirects back to the admin callback and carries upgrade intent', () => {
  assert.equal(
    buildAdminOAuthRedirectTo('https://admin.gracenote.io.kr'),
    'https://admin.gracenote.io.kr/auth/callback?next=%2Fupgrade'
  );
});

test('callback next path only accepts local paths', () => {
  assert.equal(normalizeAdminNextPath('/upgrade'), '/upgrade');
  assert.equal(normalizeAdminNextPath('https://evil.example/phish'), '/upgrade');
  assert.equal(normalizeAdminNextPath('//evil.example/phish'), '/upgrade');
});

test('member profiles from social login can continue to admin upgrade request', () => {
  assert.deepEqual(
    decideAdminAuthRedirect(
      { role: 'member', admin_status: 'none', is_master: false },
      { upgradePath: '/upgrade' }
    ),
    { path: '/upgrade', shouldSignOut: false }
  );
});

test('member upgrade redirect ignores external next path', () => {
  assert.deepEqual(
    decideAdminAuthRedirect(
      { role: 'member', admin_status: 'none', is_master: false },
      { upgradePath: 'https://evil.example/phish' }
    ),
    { path: '/upgrade', shouldSignOut: false }
  );
});

test('pending admins are signed out and shown request success', () => {
  assert.deepEqual(
    decideAdminAuthRedirect({ role: 'admin', admin_status: 'pending', is_master: false }),
    { path: '/register/success', shouldSignOut: true }
  );
});

test('approved admins go to the dashboard without using upgrade next path', () => {
  assert.deepEqual(
    decideAdminAuthRedirect(
      { role: 'admin', admin_status: 'approved', is_master: false },
      { approvedPath: '/members' }
    ),
    { path: '/members', shouldSignOut: false }
  );
});
