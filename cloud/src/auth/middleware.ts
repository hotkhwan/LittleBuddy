// Every non-health route needs a parent credential. Two forms are accepted:
//   Authorization: Bearer pt1.<...>            (account routes, Parent Corner)
//   X-Parent-Approval: pa1.<...>  or body.parentApprovalToken
//                                              (what the Godot clients already send)
// The approval token is itself parent-signed (claims pid + sub=clientId), so
// the tutor routes need nothing more than what the game sends today.
import type { MiddlewareHandler } from 'hono';
import { errors } from '../errors';
import type { Env } from '../env';
import { ensureDevParent } from '../db/parents';
import type { AuthContext, Vars } from './context';

export const PARENT_TOKEN_HEADER = 'x-parent-approval';

/** Routes that have no parent yet or authenticate another way (store webhooks: signature, Agent F). */
export function isAuthExempt(method: string, path: string): boolean {
  const p = path.replace(/^\/api/, '');
  if (p === '/healthz' || p === '/v1/health') return true;
  if (method === 'POST' && p === '/v1/parents') return true;
  if (method === 'POST' && (p === '/v1/auth/guest' || p === '/v1/auth/link')) return true;
  if (method === 'GET' && p === '/v1/me/entitlements') return true;
  if (method === 'POST' && (p === '/v1/billing/apple/notifications' || p === '/v1/billing/google/rtdn')) return true;
  return false;
}

export function tokenFrom(headers: Headers, body: unknown): string {
  const h = headers.get(PARENT_TOKEN_HEADER);
  if (h) return h.trim();
  const b = (body as Record<string, unknown> | null | undefined)?.parentApprovalToken;
  return typeof b === 'string' ? b.trim() : '';
}

export const authMiddleware: MiddlewareHandler<{ Bindings: Env; Variables: Vars }> = async (c, next) => {
  if (isAuthExempt(c.req.method, c.req.path)) {
    c.set('auth', null);
    return next();
  }
  const tokens = c.get('tokens');
  const now = c.get('now');
  const config = c.get('config');
  const body = c.get('body');

  const bearer = c.req.header('authorization') ?? '';
  if (/^bearer\s+/i.test(bearer)) {
    const r = await tokens.verifyParent(bearer.replace(/^bearer\s+/i, '').trim(), now);
    if (!r.ok) throw errors.notApproved('The parent sign-in has expired. Please sign in again.');
    const auth: AuthContext = { parentId: r.claims.pid, clientId: null, childId: null, approvalToken: null, via: 'bearer' };
    c.set('auth', auth);
    return next();
  }

  const approval = tokenFrom(c.req.raw.headers, body);
  if (!approval) throw errors.notApproved();
  const bodyClientId = (body as Record<string, unknown> | null | undefined)?.clientId;
  const bind = typeof bodyClientId === 'string' && bodyClientId ? bodyClientId : undefined;
  const r = await tokens.verifyApproval(approval, now, bind);
  if (!r.ok) throw errors.notApproved();
  if (r.dev) await ensureDevParent(c.env.DB, now, config.consentVersion);
  const auth: AuthContext = { parentId: r.claims.pid, clientId: r.claims.sub || bind || null, childId: r.claims.cid ?? null, approvalToken: approval, via: r.dev ? 'dev_literal' : 'approval' };
  c.set('auth', auth);
  return next();
};
