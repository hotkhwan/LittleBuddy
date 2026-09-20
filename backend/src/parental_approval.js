// Parent-approval tokens. The game shows its parental gate (an adult-only
// check), then obtains a token bound to the device's clientId and presents it
// when creating a tutor session. Sessions are refused without a valid token.
//
// Token format: pa1.<base64url(JSON payload)>.<hex HMAC-SHA256>
//   payload = { sub: clientId, iat: unixSeconds, exp: unixSeconds }
// The signing secret (PARENT_APPROVAL_SECRET) lives only on the server.
//
// Identity note (honest limit): the quota identity is clientId + a token bound
// to that clientId. A device without an account can be reinstalled to obtain a
// new clientId, but that requires a parent to pass the gate again and mint a
// new token; there is no way to move usage across devices without accounts.
import crypto from 'node:crypto';

const PREFIX = 'pa1';

/**
 * @param {{config: import('./config.js').Config, now: () => number}} deps
 */
export function createParentalApproval({ config, now }) {
  const secret = config.parentApprovalSecret || (config.devMode ? 'dev-only-parent-approval-secret' : '');

  /**
   * Mint a token for a clientId. Requires a secret (always present in DEV_MODE).
   * @param {string} clientId
   * @param {number} [ttlSeconds]
   */
  function mint(clientId, ttlSeconds = config.parentApprovalTtlSeconds) {
    if (!secret) throw new Error('PARENT_APPROVAL_SECRET is not configured');
    const iat = Math.floor(now() / 1000);
    const payload = { sub: clientId, iat, exp: iat + Math.max(60, ttlSeconds) };
    const body = b64url(JSON.stringify(payload));
    return `${PREFIX}.${body}.${hmac(body)}`;
  }

  /**
   * Verify a token for a clientId.
   * @param {unknown} token
   * @param {string} clientId
   * @returns {{ok: true, subject: string, dev: boolean} | {ok: false, reason: string}}
   */
  function verify(token, clientId) {
    if (typeof token !== 'string' || !token) return { ok: false, reason: 'missing' };
    if (config.devMode && token === config.devParentApprovalToken) return { ok: true, subject: clientId, dev: true };
    const parts = token.split('.');
    if (parts.length !== 3 || parts[0] !== PREFIX) return { ok: false, reason: 'malformed' };
    if (!secret) return { ok: false, reason: 'not_configured' };
    const [, body, sig] = parts;
    const expected = hmac(body);
    if (sig.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) {
      return { ok: false, reason: 'bad_signature' };
    }
    let payload;
    try {
      payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    } catch {
      return { ok: false, reason: 'malformed' };
    }
    if (payload.sub !== clientId) return { ok: false, reason: 'wrong_client' };
    if (typeof payload.exp !== 'number' || payload.exp * 1000 <= now()) return { ok: false, reason: 'expired' };
    return { ok: true, subject: payload.sub, dev: false };
  }

  /** @param {string} s */
  function hmac(s) {
    return crypto.createHmac('sha256', secret).update(s).digest('hex');
  }

  return { mint, verify, configured: Boolean(secret) };
}

/** @param {string} s */
function b64url(s) {
  return Buffer.from(s, 'utf8').toString('base64url');
}
