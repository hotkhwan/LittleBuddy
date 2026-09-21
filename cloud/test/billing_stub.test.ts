// Agent F extends these. Today the billing routes are mounted stubs.
import { describe, expect, it } from 'vitest';
import { makeClient, signInFamily } from './helpers';

describe('billing stub (Agent F)', () => {
  it('store webhooks are reachable without a parent token and answer 501 until implemented', async () => {
    const c = makeClient({ defaultToken: null });
    for (const p of ['/v1/billing/apple/notifications', '/v1/billing/google/rtdn']) {
      const r = await c.api('POST', p, { signedPayload: 'x' });
      expect(r.status, p).toBe(501);
      expect(r.body.error.code).toBe('not_implemented');
    }
  });

  it('POST /v1/billing/verify needs the parent token and is 501 until implemented', async () => {
    const c = makeClient({ defaultToken: null });
    expect((await c.api('POST', '/v1/billing/verify', {})).status).toBe(403);
    const fam = await signInFamily(c, 'buyer');
    const r = await c.api('POST', '/v1/billing/verify', { store: 'apple', transactionId: 'x' }, fam.bearer);
    expect(r.status).toBe(501);
  });

  it('billing is disabled by configuration until owner approval', async () => {
    const c = makeClient({ defaultToken: null });
    const fam = await signInFamily(c, 'buyer-2');
    const r = await c.api('GET', '/v1/entitlements', undefined, fam.bearer);
    expect(r.body.billing.enabled).toBe(false);
  });
});
