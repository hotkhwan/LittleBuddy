// Two stateless HMAC tokens, both signed with PARENT_TOKEN_SECRET:
//
//   pt1.<base64url(JSON)>.<hex HMAC>   parent bearer   payload {pid, iat, exp}
//   pa1.<base64url(JSON)>.<hex HMAC>   parental approval, payload {sub: clientId, pid, cid?, iat, exp}
//
// `pa1` is the prototype's format (backend/src/parental_approval.js: prefix,
// base64url JSON with sub/iat/exp, hex HMAC-SHA256) with two extra claims the
// Worker needs: `pid` (parent id) and optional `cid` (child id). The Godot
// clients treat the token as opaque, so nothing changes for them.
//
// In DEV_MODE the literal `dev-parent-approval` (the game's `use_dev_token()`)
// maps to the synthetic parent `dev-parent`. Never outside DEV_MODE.
import { b64urlDecode, b64urlEncode, hmacHex, timingSafeEqual } from '../util/crypto';
import { DEV_PARENT_APPROVAL_LITERAL, DEV_PARENT_ID } from '../env';

export interface ParentClaims { pid: string; iat: number; exp: number }
export interface ApprovalClaims { sub: string; pid: string; cid?: string; iat: number; exp: number }

export type VerifyResult<T> = { ok: true; claims: T; dev: boolean } | { ok: false; reason: 'missing' | 'malformed' | 'bad_signature' | 'expired' | 'not_configured' | 'wrong_client' };

export class TokenService {
  constructor(private readonly secret: string, private readonly devMode: boolean) {}

  get configured(): boolean {
    return this.secret.length >= 16;
  }

  async mintParent(parentId: string, nowMs: number, ttlSeconds: number): Promise<string> {
    const iat = Math.floor(nowMs / 1000);
    return this.sign('pt1', { pid: parentId, iat, exp: iat + Math.max(60, ttlSeconds) });
  }

  async mintApproval(input: { clientId: string; parentId: string; childId?: string }, nowMs: number, ttlSeconds: number): Promise<string> {
    const iat = Math.floor(nowMs / 1000);
    const claims: ApprovalClaims = { sub: input.clientId, pid: input.parentId, iat, exp: iat + Math.max(60, ttlSeconds) };
    if (input.childId) claims.cid = input.childId;
    return this.sign('pa1', claims);
  }

  async verifyParent(token: unknown, nowMs: number): Promise<VerifyResult<ParentClaims>> {
    const r = await this.verify<ParentClaims>('pt1', token, nowMs);
    if (r.ok && typeof r.claims.pid !== 'string') return { ok: false, reason: 'malformed' };
    return r;
  }

  /** `clientId` is optional: when given, the token must be bound to it (prototype rule). */
  async verifyApproval(token: unknown, nowMs: number, clientId?: string): Promise<VerifyResult<ApprovalClaims>> {
    if (this.devMode && token === DEV_PARENT_APPROVAL_LITERAL) {
      return { ok: true, dev: true, claims: { sub: clientId ?? '', pid: DEV_PARENT_ID, iat: 0, exp: Number.MAX_SAFE_INTEGER } };
    }
    const r = await this.verify<ApprovalClaims>('pa1', token, nowMs);
    if (!r.ok) return r;
    if (typeof r.claims.sub !== 'string' || typeof r.claims.pid !== 'string') return { ok: false, reason: 'malformed' };
    if (clientId !== undefined && r.claims.sub !== clientId) return { ok: false, reason: 'wrong_client' };
    return r;
  }

  private async sign(prefix: 'pt1' | 'pa1', claims: object): Promise<string> {
    if (!this.configured) throw new Error('PARENT_TOKEN_SECRET is not configured');
    const body = b64urlEncode(JSON.stringify(claims));
    return `${prefix}.${body}.${await hmacHex(this.secret, prefix, body)}`;
  }

  private async verify<T extends { exp: number }>(prefix: string, token: unknown, nowMs: number): Promise<VerifyResult<T>> {
    if (typeof token !== 'string' || !token) return { ok: false, reason: 'missing' };
    const parts = token.split('.');
    if (parts.length !== 3 || parts[0] !== prefix) return { ok: false, reason: 'malformed' };
    if (!this.configured) return { ok: false, reason: 'not_configured' };
    const [, body, sig] = parts;
    const expected = await hmacHex(this.secret, prefix, body);
    if (!timingSafeEqual(sig, expected)) return { ok: false, reason: 'bad_signature' };
    const json = b64urlDecode(body);
    if (json === null) return { ok: false, reason: 'malformed' };
    let claims: T;
    try {
      claims = JSON.parse(json) as T;
    } catch {
      return { ok: false, reason: 'malformed' };
    }
    if (!claims || typeof claims !== 'object' || typeof claims.exp !== 'number' || claims.exp * 1000 <= nowMs) return { ok: false, reason: 'expired' };
    return { ok: true, claims, dev: false };
  }
}
