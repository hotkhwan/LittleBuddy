import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { startServer, createSession, tempDir } from './helpers.js';
import { createStore } from '../src/store.js';

test('entitlement: default free, dev grant/revoke, reflected in sessions', async () => {
  const s = await startServer();
  try {
    const e0 = await s.api('GET', '/api/v1/tutor/entitlement?clientId=kid1');
    assert.equal(e0.body.entitlement, 'free');
    assert.equal(e0.body.quota.dailyAllowanceSeconds, 300);
    const grant = await s.api('POST', '/api/v1/dev/entitlement', { clientId: 'kid1', entitlement: 'family_club' });
    assert.equal(grant.status, 200);
    const e1 = await s.api('GET', '/api/v1/tutor/entitlement?clientId=kid1');
    assert.equal(e1.body.entitlement, 'family_club');
    assert.equal(e1.body.quota.dailyAllowanceSeconds, 1800);
    const c = await createSession(s.api, { clientId: 'kid1' });
    assert.equal(c.body.entitlement, 'family_club');
    const bad = await s.api('POST', '/api/v1/dev/entitlement', { clientId: 'kid1', entitlement: 'unlimited' });
    assert.equal(bad.status, 400);
    const revoke = await s.api('POST', '/api/v1/dev/entitlement', { clientId: 'kid1', entitlement: 'free' });
    assert.equal(revoke.body.entitlement, 'free');
  } finally {
    await s.close();
  }
});

test('mock billing: purchase mints a receipt, the SERVER validates it; tampering and cross-client use are refused', async () => {
  const s = await startServer();
  try {
    const p = await s.api('POST', '/api/v1/dev/billing/mock-purchase', { clientId: 'kid2', productId: 'little_days.family_club.monthly' });
    assert.equal(p.status, 200);
    assert.equal(p.body.platform, 'mock');
    assert.ok(p.body.receipt.signature);
    // Client claiming an entitlement directly changes nothing.
    const still = await s.api('GET', '/api/v1/tutor/entitlement?clientId=kid2');
    assert.equal(still.body.entitlement, 'free');

    const tampered = { ...p.body.receipt, productId: 'little_days.family_club.yearly' };
    const t = await s.api('POST', '/api/v1/tutor/billing/validate', { clientId: 'kid2', platform: 'mock', receipt: tampered });
    assert.equal(t.status, 400);
    const cross = await s.api('POST', '/api/v1/tutor/billing/validate', { clientId: 'kid3', platform: 'mock', receipt: p.body.receipt });
    assert.equal(cross.status, 400);

    const v = await s.api('POST', '/api/v1/tutor/billing/validate', { clientId: 'kid2', platform: 'mock', receipt: p.body.receipt });
    assert.equal(v.status, 200);
    assert.equal(v.body.entitlement, 'family_club');
    assert.equal(v.body.quota.dailyAllowanceSeconds, 1800);
    const restore = await s.api('POST', '/api/v1/tutor/billing/validate', { clientId: 'kid2', platform: 'mock', receipt: p.body.receipt });
    assert.equal(restore.status, 200, 'restore purchase for the same client is fine');

    // Expiry is honoured.
    s.clock.t = Date.parse(p.body.receipt.expiresAt) + 1000;
    const expired = await s.api('GET', '/api/v1/tutor/entitlement?clientId=kid2');
    assert.equal(expired.body.entitlement, 'free');

    const gp = await s.api('POST', '/api/v1/tutor/billing/validate', { clientId: 'kid2', platform: 'google_play', receipt: { purchaseToken: 'x' } });
    assert.equal(gp.status, 501);
    const ap = await s.api('POST', '/api/v1/tutor/billing/validate', { clientId: 'kid2', platform: 'apple', receipt: { jws: 'x' } });
    assert.equal(ap.status, 501);
    const unknownProduct = await s.api('POST', '/api/v1/dev/billing/mock-purchase', { clientId: 'kid2', productId: 'gold_coins' });
    assert.equal(unknownProduct.status, 400);
  } finally {
    await s.close();
  }
});

test('mock billing validation is refused outside DEV_MODE; dev routes are 404', async () => {
  const s = await startServer({ env: { DEV_MODE: '0' } });
  try {
    const p = await s.api('POST', '/api/v1/dev/billing/mock-purchase', { clientId: 'kid' });
    assert.equal(p.status, 404);
    const g = await s.api('POST', '/api/v1/dev/entitlement', { clientId: 'kid', entitlement: 'family_club' });
    assert.equal(g.status, 404);
    const v = await s.api('POST', '/api/v1/tutor/billing/validate', { clientId: 'kid', platform: 'mock', receipt: {} });
    assert.equal(v.status, 501);
  } finally {
    await s.close();
  }
});

test('store: persists per collection, survives reload, quarantines corrupt files', () => {
  const dir = tempDir();
  const a = createStore({ dataDir: dir });
  a.usage.set('u1', { dayKey: '2026-09-20', usedSeconds: 42 });
  a.sessions.set('s1', { sessionId: 's1' });
  assert.ok(fs.existsSync(path.join(dir, 'usage.json')));
  const b = createStore({ dataDir: dir });
  assert.deepEqual(b.usage.get('u1'), { dayKey: '2026-09-20', usedSeconds: 42 });
  assert.equal(b.sessions.size(), 1);
  fs.writeFileSync(path.join(dir, 'usage.json'), '{corrupt', 'utf8');
  const c = createStore({ dataDir: dir });
  assert.equal(c.usage.get('u1'), undefined, 'corrupt file -> safe empty default');
  assert.ok(fs.readdirSync(dir).some((f) => f.startsWith('usage.json.corrupt-')));
  assert.equal(c.sessions.size(), 1, 'other collections unaffected');
});
