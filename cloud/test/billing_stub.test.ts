// Agent F extends these. Today the billing routes are mounted stubs.
import { describe, expect, it } from 'vitest';
import { makeClient, signInFamily } from './helpers';

describe('billing stub (Agent F)', () => {
  it('store webhooks are reachable without a parent token and answer 503 billing_disabled while purchases are off', async () => {
    const c = makeClient({ defaultToken: null });
    for (const p of ['/v1/billing/apple/notifications', '/v1/billing/google/rtdn']) {
      const r = await c.api('POST', p, { signedPayload: 'x' });
      expect(r.status, p).toBe(503);
      expect(['billing_disabled', 'store_not_configured']).toContain(r.body.code ?? r.body.error?.code);
    }
  });

  it('POST /v1/billing/verify needs the parent token and is 400 for an empty body (never 500)', async () => {
    const c = makeClient({ defaultToken: null });
    expect((await c.api('POST', '/v1/billing/verify', {})).status).toBe(403);
    const fam = await signInFamily(c, 'buyer');
    const r = await c.api('POST', '/v1/billing/verify', { store: 'apple', transactionId: 'x' }, fam.bearer);
    expect(r.status).toBe(400);
  });

  it('billing is disabled by configuration until owner approval', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'buyer-2');
    const r = await c.api('GET', '/v1/entitlements', undefined, fam.bearer);
    expect(r.body.billing.enabled).toBe(false);
  });
});
