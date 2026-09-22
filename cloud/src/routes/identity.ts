import { Hono } from 'hono';
import type { Env } from '../env';
import type { Vars } from '../auth/context';
import { ApiError, errors } from '../errors';
import { str } from '../util/validate';
import { hmacHex, uuid } from '../util/crypto';
import { createIdentityVerifiers, hashSubject, IdentityError, failureStatus, type IdentityEnv } from '../auth/identity';
import { upsertParent } from '../db/parents';

export const identityRoutes = new Hono<{ Bindings: Env; Variables: Vars }>();
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const PLATFORMS = ['ios', 'android', 'macos', 'windows', 'linux', 'web', 'unknown'] as const;

function bearer(c: { req: { header(name: string): string | undefined } }): string {
  return (c.req.header('authorization') ?? '').replace(/^bearer\s+/i, '').trim();
}

async function requireGuest(c: Parameters<typeof bearer>[0] & { get(k: 'tokens'): Vars['tokens']; get(k: 'now'): number; env: Env }) {
  const checked = await c.get('tokens').verifyGuest(bearer(c), c.get('now'));
  if (!checked.ok) throw new ApiError(401, 'invalid_guest_session', 'The guest session is missing or expired.');
  const row = await c.env.DB.prepare('SELECT id,status,merged_into FROM guest_accounts WHERE id = ?').bind(checked.claims.gid).first<{ id: string; status: string; merged_into: string | null }>();
  if (!row) throw new ApiError(401, 'invalid_guest_session', 'The guest account no longer exists.');
  const install = await c.env.DB.prepare("SELECT guest_account_id,status FROM installations WHERE installation_id = ?").bind(checked.claims.iid).first<{ guest_account_id: string | null; status: string }>();
  if (!install || install.guest_account_id !== row.id || install.status !== 'active') throw new ApiError(401, 'guest_token_replay', 'This guest session belongs to another installation.');
  return { claims: checked.claims, row };
}

identityRoutes.post('/auth/guest', async (c) => {
  if (!c.get('tokens').configured) throw errors.providerUnavailable('PARENT_TOKEN_SECRET is not configured on this server.');
  const body = c.get('body');
  const installationId = str(body, 'installationId', { required: true, max: 36 });
  if (!UUID_RE.test(installationId)) throw errors.badRequest('installationId must be an app-generated UUID.');
  const platform = str(body, 'platform', { max: 16 }) || 'unknown';
  if (!(PLATFORMS as readonly string[]).includes(platform)) throw errors.badRequest(`platform must be one of ${PLATFORMS.join(', ')}`);
  const appVersion = str(body, 'appVersion', { max: 32 }) || null;
  const now = c.get('now');
  const existing = await c.env.DB.prepare('SELECT guest_account_id,account_id,status FROM installations WHERE installation_id = ?').bind(installationId).first<{ guest_account_id: string | null; account_id: string | null; status: string }>();
  if (existing?.account_id) throw errors.conflict('This installation is already linked to a parent account.');
  let guestAccountId = existing?.guest_account_id ?? null;
  if (guestAccountId) {
    const guest = await c.env.DB.prepare('SELECT status FROM guest_accounts WHERE id = ?').bind(guestAccountId).first<{ status: string }>();
    if (!guest || guest.status !== 'active' || existing?.status !== 'active') throw errors.conflict('This guest account has already been linked or revoked.');
    await c.env.DB.prepare('UPDATE installations SET platform=?, app_version=?, last_seen_at=? WHERE installation_id=?').bind(platform, appVersion, now, installationId).run();
  } else {
    guestAccountId = uuid();
    await c.env.DB.batch([
      c.env.DB.prepare('INSERT INTO guest_accounts (id,status,created_at,updated_at) VALUES (?,\'active\',?,?)').bind(guestAccountId, now, now),
      c.env.DB.prepare('INSERT INTO installations (installation_id,platform,guest_account_id,app_version,created_at,last_seen_at,status) VALUES (?,?,?,?,?,?,\'active\')').bind(installationId, platform, guestAccountId, appVersion, now, now),
    ]);
  }
  const guestToken = await c.get('tokens').mintGuest(guestAccountId, installationId, now, c.get('config').parentTokenTtlSeconds);
  return c.json({ guestAccountId, installationId, guestToken, accountType: 'guest' }, existing ? 200 : 201);
});

identityRoutes.post('/auth/link', async (c) => {
  const guest = await requireGuest(c);
  if (guest.row.status === 'linked') throw errors.conflict('This guest was already linked.');
  if (guest.row.status !== 'active') throw errors.notApproved('This guest account cannot be linked.');
  const body = c.get('body');
  const provider = str(body, 'provider', { required: true, max: 16 });
  if (provider !== 'apple' && provider !== 'google') throw errors.badRequest('provider must be apple or google');
  const identityToken = str(body, 'identityToken', { required: true, max: 8192 });
  const nonce = str(body, 'nonce', { max: 256 });
  let verified;
  try {
    verified = await createIdentityVerifiers(c.get('config'), c.env as Env & IdentityEnv, { now: () => c.get('now') })[provider].verify(identityToken, nonce ? { nonce } : {});
  } catch (error) {
    if (!(error instanceof IdentityError)) throw error;
    const status = failureStatus(error.reason);
    throw new ApiError(status, status === 503 ? 'provider_unavailable' : 'not_approved', error.message, { reason: error.reason });
  }
  const now = c.get('now');
  const subjectHash = await hashSubject(c.env.PARENT_TOKEN_SECRET!, provider, verified.subject);
  const mapped = await c.env.DB.prepare('SELECT account_id FROM identity_providers WHERE provider=? AND provider_subject_hash=?').bind(provider, subjectHash).first<{ account_id: string }>();
  let accountId = mapped?.account_id;
  if (!accountId) {
    const legacy = await upsertParent(c.env.DB, { provider, subjectHash, emailHash: verified.emailHash, now });
    if (legacy.tombstoned) throw errors.conflict('This provider identity belongs to a recently deleted account.');
    accountId = legacy.parent.id;
    await c.env.DB.batch([
      c.env.DB.prepare('INSERT OR IGNORE INTO accounts (id,status,created_at,updated_at) VALUES (?,\'active\',?,?)').bind(accountId, now, now),
      c.env.DB.prepare('INSERT OR IGNORE INTO parent_profiles (id,account_id,created_at,updated_at) VALUES (?,?,?,?)').bind(uuid(), accountId, now, now),
      c.env.DB.prepare('INSERT INTO identity_providers (provider,provider_subject_hash,account_id,created_at,last_seen_at) VALUES (?,?,?,?,?)').bind(provider, subjectHash, accountId, now, now),
    ]);
  } else {
    await c.env.DB.prepare('UPDATE identity_providers SET last_seen_at=? WHERE provider=? AND provider_subject_hash=?').bind(now, provider, subjectHash).run();
  }
  await mergeGuest(c.env.DB, guest.row.id, accountId, guest.claims.iid, now);
  const parentToken = await c.get('tokens').mintParent(accountId, now, c.get('config').parentTokenTtlSeconds);
  return c.json({ parentAccountId: accountId, linkedGuestAccountId: guest.row.id, parentToken, provider, mergeStatus: 'complete' });
});

identityRoutes.get('/me/purchase-identity', async (c) => {
  const p = await c.get('tokens').verifyParent(bearer(c), c.get('now'));
  if (!p.ok) throw new ApiError(403, 'parent_account_required', 'Link a parent account before purchasing.');
  const now = c.get('now');
  let apple = await c.env.DB.prepare("SELECT mapping_value FROM purchase_identity_mappings WHERE account_id=? AND platform='apple'").bind(p.claims.pid).first<{ mapping_value: string }>();
  if (!apple) {
    const value = uuid();
    await c.env.DB.prepare("INSERT INTO purchase_identity_mappings (account_id,platform,mapping_value,created_at) VALUES (?,'apple',?,?)").bind(p.claims.pid, value, now).run();
    apple = { mapping_value: value };
  }
  const googleValue = await hmacHex(c.env.PARENT_TOKEN_SECRET!, 'google-obfuscated-account-id', p.claims.pid);
  await c.env.DB.prepare("INSERT OR IGNORE INTO purchase_identity_mappings (account_id,platform,mapping_value,created_at) VALUES (?,'google',?,?)").bind(p.claims.pid, googleValue, now).run();
  return c.json({ apple: { appAccountToken: apple.mapping_value }, google: { obfuscatedAccountId: googleValue }, containsPii: false });
});

export async function mergeGuest(db: D1Database, guestId: string, accountId: string, installationId: string, now: number): Promise<void> {
  const current = await db.prepare('SELECT status,merged_into FROM guest_accounts WHERE id=?').bind(guestId).first<{ status: string; merged_into: string | null }>();
  if (!current) throw errors.notFound('Guest account not found.');
  if (current.status === 'linked') {
    if (current.merged_into === accountId) return;
    throw errors.conflict('This guest is already linked to another account.');
  }
  if (current.status === 'linking' && current.merged_into !== accountId) throw errors.conflict('This guest is being linked to another account.');
  if (current.status !== 'active' && current.status !== 'linking') throw errors.conflict('This guest cannot be linked.');
  if (current.status === 'active') {
    const claimed = await db.prepare("UPDATE guest_accounts SET status='linking',merged_into=?,updated_at=? WHERE id=? AND status='active'").bind(accountId, now, guestId).run();
    if (Number(claimed.meta.changes ?? 0) !== 1) throw errors.conflict('This guest link is already in progress.');
  }
  await db.batch([
    db.prepare(`INSERT INTO account_learning_progress (account_id,lesson_id,mastery,evidence_at,completed_at,stars,updated_at)
      SELECT ?,lesson_id,mastery,evidence_at,completed_at,stars,? FROM guest_learning_progress WHERE guest_account_id=?
      ON CONFLICT(account_id,lesson_id) DO UPDATE SET
       mastery=CASE WHEN excluded.mastery>account_learning_progress.mastery OR (excluded.mastery=account_learning_progress.mastery AND excluded.evidence_at>account_learning_progress.evidence_at) THEN excluded.mastery ELSE account_learning_progress.mastery END,
       evidence_at=MAX(account_learning_progress.evidence_at,excluded.evidence_at), completed_at=COALESCE(account_learning_progress.completed_at,excluded.completed_at), stars=MAX(account_learning_progress.stars,excluded.stars), updated_at=excluded.updated_at`).bind(accountId, now, guestId),
    db.prepare('INSERT OR IGNORE INTO account_reward_awards SELECT ?,award_id,reward_key,awarded_at FROM guest_reward_awards WHERE guest_account_id=?').bind(accountId, guestId),
    db.prepare('INSERT OR IGNORE INTO account_unlocks SELECT ?,unlock_key,unlocked_at FROM guest_unlocks WHERE guest_account_id=?').bind(accountId, guestId),
    db.prepare('INSERT OR IGNORE INTO account_settings SELECT ?,setting_key,value_json,updated_at FROM guest_settings WHERE guest_account_id=?').bind(accountId, guestId),
    db.prepare(`INSERT INTO account_ai_usage (account_id,usage_period,standard_seconds,input_tokens,output_tokens,updated_at)
      SELECT ?,usage_period,standard_seconds,input_tokens,output_tokens,? FROM guest_ai_usage g WHERE guest_account_id=?
      AND NOT EXISTS (SELECT 1 FROM account_ai_usage_imports i WHERE i.guest_account_id=g.guest_account_id AND i.usage_period=g.usage_period)
      ON CONFLICT(account_id,usage_period) DO UPDATE SET standard_seconds=account_ai_usage.standard_seconds+excluded.standard_seconds,input_tokens=account_ai_usage.input_tokens+excluded.input_tokens,output_tokens=account_ai_usage.output_tokens+excluded.output_tokens,updated_at=excluded.updated_at`).bind(accountId, now, guestId),
    db.prepare('INSERT OR IGNORE INTO account_ai_usage_imports SELECT guest_account_id,?,usage_period,standard_seconds,input_tokens,output_tokens,? FROM guest_ai_usage WHERE guest_account_id=?').bind(accountId, now, guestId),
    db.prepare("UPDATE guest_accounts SET status='linked',merged_into=?,linked_at=?,updated_at=? WHERE id=? AND status='linking' AND merged_into=?").bind(accountId, now, now, guestId, accountId),
    db.prepare('UPDATE installations SET account_id=?,guest_account_id=NULL,last_seen_at=? WHERE installation_id=? AND guest_account_id=?').bind(accountId, now, installationId, guestId),
  ]);
}
