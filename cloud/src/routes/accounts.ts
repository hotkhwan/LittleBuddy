// Parents, children, devices, consent, entitlements, progress, and the parent
// portal's privacy controls (export, account deletion, child deletion).
import { Hono } from 'hono';
import { DEV_PARENT_ID, type Env } from '../env';
import { requireAuth, type AppContext, type AuthContext, type Vars } from '../auth/context';
import { ApiError, errors } from '../errors';
import { ID_RE, boolField, intField, str } from '../util/validate';
import { getParent, upsertParent, type ParentRow } from '../db/parents';
import { childToJson, createChild, getChild, listChildren } from '../db/children';
import { PLATFORMS, listDevices, upsertDevice } from '../db/devices';
import { CONSENT_KINDS, consentToJson, listConsent, setConsent, type ConsentKind } from '../db/consent';
import { effectiveEntitlement, listEntitlements } from '../db/entitlements';
import { listProgress, progressToJson, upsertProgress } from '../db/progress';
import { deleteChild, deleteParentAccount, exportFamily } from '../db/accounts_privacy';
import { LESSONS } from '../tutor/lessons';
import { IdentityError, createIdentityVerifiers, failureStatus, hashSubject, isIdentityProvider, type IdentityEnv } from '../auth/identity';

export const accountRoutes = new Hono<{ Bindings: Env; Variables: Vars }>();

const NICKNAME_RE = /^[\p{L}\p{N} '._-]{1,24}$/u;
const BUCKET_RE = /^\d{4}-\d{4}$/;
const LOCALE_RE = /^[a-z]{2,3}(-[A-Za-z]{2,4})?$/;
const SEMVER_RE = /^[0-9A-Za-z.+-]{1,32}$/;
const MAX_CHILDREN = 6; // the DEV_MODE literal parent is exempt so local test runs can mint a child per session
const MAX_IDENTITY_TOKEN = 8192;

/**
 * A credential is not enough on its own: the parent behind it must still
 * exist (a `pt1` survives DELETE /v1/parents/me until it expires). One
 * indexed read per account call.
 */
async function requireLiveParent(c: AppContext): Promise<{ auth: AuthContext; parent: ParentRow }> {
  const auth = requireAuth(c);
  const parent = await getParent(c.env.DB, auth.parentId);
  if (!parent || parent.deleted_at !== null) throw errors.notApproved('This account no longer exists. Please sign in again.');
  return { auth, parent };
}

/** Portal-only actions (consent, export, deletion) need the parent sign-in, never a device approval. */
function requireBearer(auth: AuthContext, what: string): void {
  if (auth.via !== 'bearer') throw errors.notApproved(`${what} needs the parent sign-in, not a device approval.`);
}

// ---------------------------------------------------------------- parents
// Sign-in. `provider` picks the verifier (cloud/src/auth/identity): `apple`
// and `google` verify an identity token against the provider's JWKS,
// `dev` (DEV_MODE only) accepts a literal subject. The parent is found or
// created by (provider, HMAC(subject)); the raw subject and e-mail are never
// stored. A deleted account's tombstone answers 409 for 30 days.
accountRoutes.post('/parents', async (c) => {
  const config = c.get('config');
  const now = c.get('now');
  const body = c.get('body');
  const tokens = c.get('tokens');
  const provider = str(body, 'provider', { required: true, max: 16 });
  if (!isIdentityProvider(provider)) throw errors.badRequest('provider must be dev, apple or google');
  if (!tokens.configured) throw errors.providerUnavailable('PARENT_TOKEN_SECRET is not configured on this server.');
  const clientId = str(body, 'clientId', { max: 128, re: ID_RE });
  const credential = provider === 'dev' ? str(body, 'subject', { required: true, max: 128, re: ID_RE }) : str(body, 'identityToken', { required: true, max: MAX_IDENTITY_TOKEN });
  const nonce = str(body, 'nonce', { max: 256 });

  const verifiers = createIdentityVerifiers(config, c.env as Env & IdentityEnv, { now: () => now });
  let identity;
  try {
    identity = await verifiers[provider].verify(credential, nonce ? { nonce } : {});
  } catch (error) {
    if (!(error instanceof IdentityError)) throw error;
    const status = failureStatus(error.reason);
    if (status === 501) throw errors.notImplemented(error.message);
    if (status === 503) throw errors.providerUnavailable(error.message);
    if (status === 400) throw errors.badRequest('identityToken is not a valid identity token.', { reason: error.reason });
    throw new ApiError(403, 'not_approved', 'The sign-in could not be verified. Please sign in again.', { reason: error.reason });
  }

  const subjectHash = await hashSubject(c.env.PARENT_TOKEN_SECRET!, identity.provider, identity.subject);
  const outcome = await upsertParent(c.env.DB, { provider: identity.provider, subjectHash, emailHash: identity.emailHash ?? null, now });
  if (outcome.tombstoned) {
    const availableAt = new Date(outcome.tombstoned.tombstone_until ?? now).toISOString();
    throw new ApiError(409, 'conflict', 'This account was deleted recently. A new account can be created after the waiting period.', { reason: 'account_deleted', availableAt });
  }
  const { parent, created } = outcome;
  const parentToken = await tokens.mintParent(parent.id, now, config.parentTokenTtlSeconds);
  const out: Record<string, unknown> = {
    parentId: parent.id,
    provider: parent.provider,
    created,
    parentToken,
    expiresAt: new Date(now + config.parentTokenTtlSeconds * 1000).toISOString(),
    emailVerified: identity.emailVerified,
    devMode: config.devMode,
  };
  if (clientId) out.parentApprovalToken = await tokens.mintApproval({ clientId, parentId: parent.id }, now, config.parentTokenTtlSeconds);
  return c.json(out, 201);
});

accountRoutes.get('/parents/me', async (c) => {
  const { auth, parent } = await requireLiveParent(c);
  const config = c.get('config');
  const children = await listChildren(c.env.DB, parent.id);
  const eff = effectiveEntitlement(await listEntitlements(c.env.DB, parent.id), config, c.get('now'));
  return c.json({
    parentId: parent.id,
    provider: parent.provider,
    consentVersion: parent.consent_version,
    requiredConsentVersion: config.consentVersion,
    hasEmailHash: parent.email_hash !== null,
    createdAt: new Date(parent.created_at).toISOString(),
    via: auth.via,
    childCount: children.length,
    maxChildren: MAX_CHILDREN,
    tutorEntitlement: eff.entitlement,
  });
});

// The server half of the parental gate: a signed-in parent binds approval to a device (and optionally a child).
accountRoutes.post('/parents/approval', async (c) => {
  const { auth } = await requireLiveParent(c);
  const config = c.get('config');
  const now = c.get('now');
  const body = c.get('body');
  const clientId = str(body, 'clientId', { required: true, max: 128, re: ID_RE });
  const childId = str(body, 'childId', { max: 64 });
  if (childId && !(await getChild(c.env.DB, auth.parentId, childId))) throw errors.notFound('Child not found.');
  const ttl = Math.min(config.parentTokenTtlSeconds, Math.max(60, intField(body, 'ttlSeconds', { min: 60, max: config.parentTokenTtlSeconds, fallback: config.parentTokenTtlSeconds })));
  const token = await c.get('tokens').mintApproval({ clientId, parentId: auth.parentId, childId: childId || undefined }, now, ttl);
  return c.json({ clientId, childId: childId || null, parentApprovalToken: token, expiresAt: new Date(now + ttl * 1000).toISOString() }, 201);
});

// Read-only subscription view for the portal. Billing (cloud/src/billing)
// writes entitlements; this route only reads them.
accountRoutes.get('/parents/me/subscription', async (c) => {
  const { parent } = await requireLiveParent(c);
  const config = c.get('config');
  const now = c.get('now');
  const rows = await listEntitlements(c.env.DB, parent.id);
  const eff = effectiveEntitlement(rows, config, now);
  const current = rows.find((r) => config.familyClubProductIds.includes(r.product_id) && (r.status === 'active' || r.status === 'grace') && (r.period_end === null || r.period_end > now)) ?? null;
  return c.json({
    parentId: parent.id,
    entitlement: eff.entitlement,
    status: current ? current.status : rows.length ? 'inactive' : 'none',
    activeUntil: eff.activeUntil,
    managedBy: eff.source,
    productId: current?.product_id ?? null,
    billing: { enabled: config.billingEnabled },
    priceHint: config.priceHint,
    records: rows.map((r) => ({ productId: r.product_id, source: r.source, status: r.status, periodEnd: r.period_end === null ? null : new Date(r.period_end).toISOString(), updatedAt: new Date(r.updated_at).toISOString() })),
  });
});

// Data export: every row of the family, ids and numbers only.
accountRoutes.get('/parents/me/export', async (c) => {
  const { auth, parent } = await requireLiveParent(c);
  requireBearer(auth, 'Exporting the family data');
  const body = await exportFamily(c.env.DB, parent, c.get('config').consentVersion, c.get('now'));
  c.header('content-disposition', 'attachment; filename="little-days-family-export.json"');
  c.header('cache-control', 'no-store');
  return c.json(body);
});

// Account deletion: children, devices, consent, progress, sessions, quota
// mirrors, idempotency rows and the per-child quota counters go; entitlements
// are marked revoked (audit) and purchase events lose their parent link; the
// parent row becomes a 30-day tombstone.
accountRoutes.delete('/parents/me', async (c) => {
  const { auth, parent } = await requireLiveParent(c);
  requireBearer(auth, 'Deleting the account');
  if (parent.id === DEV_PARENT_ID) throw errors.badRequest('The DEV_MODE literal parent cannot be deleted.');
  const now = c.get('now');
  const result = await deleteParentAccount(c.env.DB, parent.id, now);
  for (const childId of result.childIds) await c.env.QUOTA.get(c.env.QUOTA.idFromName(childId)).reset();
  return c.json({ deleted: true, parentId: parent.id, deletedAt: new Date(now).toISOString(), tombstoneUntil: new Date(result.tombstoneUntil).toISOString(), counts: result.counts });
});

// --------------------------------------------------------------- children
accountRoutes.get('/children', async (c) => {
  const { auth } = await requireLiveParent(c);
  return c.json({ children: (await listChildren(c.env.DB, auth.parentId)).map(childToJson) });
});

function readNickname(body: unknown, required: boolean): string {
  const nickname = str(body, 'nickname', { required, max: 24 }).trim();
  if (!required && !nickname) return '';
  if (!NICKNAME_RE.test(nickname)) throw errors.badRequest('nickname must be 1-24 letters, digits or spaces');
  if (/@|https?:|www\./i.test(nickname)) throw errors.badRequest('nickname must not contain contact details');
  return nickname;
}

accountRoutes.post('/children', async (c) => {
  const { auth } = await requireLiveParent(c);
  const body = c.get('body');
  const nickname = readNickname(body, true);
  const avatarId = str(body, 'avatarId', { max: 40, re: ID_RE });
  const birthYearBucket = str(body, 'birthYearBucket', { max: 9, re: BUCKET_RE });
  const locale = str(body, 'locale', { max: 8, re: LOCALE_RE });
  const existing = await listChildren(c.env.DB, auth.parentId);
  if (existing.length >= MAX_CHILDREN && !(c.get('config').devMode && auth.parentId === DEV_PARENT_ID)) throw errors.badRequest(`a family can have at most ${MAX_CHILDREN} child profiles`);
  const child = await createChild(c.env.DB, { parentId: auth.parentId, nickname, avatarId: avatarId || undefined, birthYearBucket: birthYearBucket || undefined, locale: locale || undefined, now: c.get('now') });
  return c.json(childToJson(child), 201);
});

accountRoutes.get('/children/:id', async (c) => {
  const { auth } = await requireLiveParent(c);
  const child = await getChild(c.env.DB, auth.parentId, c.req.param('id'));
  if (!child) throw errors.notFound('Child not found.');
  return c.json(childToJson(child));
});

// Edit nickname / avatar / birth-year bucket / locale (portal; parent sign-in only).
accountRoutes.patch('/children/:id', async (c) => {
  const { auth } = await requireLiveParent(c);
  requireBearer(auth, 'Editing a child profile');
  const body = c.get('body');
  const child = await getChild(c.env.DB, auth.parentId, c.req.param('id'));
  if (!child) throw errors.notFound('Child not found.');
  const nickname = readNickname(body, false);
  const avatarId = str(body, 'avatarId', { max: 40, re: ID_RE });
  const birthYearBucket = str(body, 'birthYearBucket', { max: 9, re: BUCKET_RE });
  const locale = str(body, 'locale', { max: 8, re: LOCALE_RE });
  const clearBucket = (body as Record<string, unknown> | null)?.birthYearBucket === null;
  await c.env.DB.prepare('UPDATE child_profiles SET nickname = COALESCE(?, nickname), avatar_id = COALESCE(?, avatar_id), birth_year_bucket = CASE WHEN ? THEN NULL ELSE COALESCE(?, birth_year_bucket) END, locale = COALESCE(?, locale), updated_at = ? WHERE id = ? AND parent_id = ?')
    .bind(nickname || null, avatarId || null, clearBucket ? 1 : 0, birthYearBucket || null, locale || null, c.get('now'), child.id, auth.parentId).run();
  return c.json(childToJson((await getChild(c.env.DB, auth.parentId, child.id))!));
});

// Delete one child and everything keyed by it (progress, sessions, quota).
accountRoutes.delete('/children/:id', async (c) => {
  const { auth } = await requireLiveParent(c);
  requireBearer(auth, 'Deleting a child profile');
  const childId = c.req.param('id');
  const counts = await deleteChild(c.env.DB, auth.parentId, childId);
  if (!counts) throw errors.notFound('Child not found.');
  await c.env.QUOTA.get(c.env.QUOTA.idFromName(childId)).reset();
  return c.json({ deleted: true, childId, counts });
});

// ---------------------------------------------------------------- devices
accountRoutes.get('/devices', async (c) => {
  const { auth } = await requireLiveParent(c);
  const rows = await listDevices(c.env.DB, auth.parentId);
  return c.json({ devices: rows.map((d) => ({ deviceId: d.id, platform: d.platform, appVersion: d.app_version, createdAt: new Date(d.created_at).toISOString(), lastSeenAt: new Date(d.last_seen_at).toISOString() })) });
});

accountRoutes.post('/devices', async (c) => {
  const { auth } = await requireLiveParent(c);
  const body = c.get('body');
  const clientId = str(body, 'clientId', { required: true, max: 128, re: ID_RE });
  if (auth.clientId && auth.clientId !== clientId) throw errors.notApproved('This approval is bound to another device.');
  const platform = str(body, 'platform', { max: 16 }) || 'unknown';
  if (!(PLATFORMS as readonly string[]).includes(platform)) throw errors.badRequest(`platform must be one of ${PLATFORMS.join(', ')}`);
  const appVersion = str(body, 'appVersion', { max: 32, re: SEMVER_RE });
  const row = await upsertDevice(c.env.DB, { id: clientId, parentId: auth.parentId, platform, appVersion: appVersion || undefined, now: c.get('now') });
  if (!row) throw errors.conflict('This device is registered to another family.');
  return c.json({ deviceId: row.id, platform: row.platform, appVersion: row.app_version, lastSeenAt: new Date(row.last_seen_at).toISOString() }, 201);
});

// ---------------------------------------------------------------- consent
accountRoutes.get('/consent', async (c) => {
  const { auth } = await requireLiveParent(c);
  const config = c.get('config');
  const rows = await listConsent(c.env.DB, auth.parentId);
  return c.json({ parentId: auth.parentId, requiredVersion: config.consentVersion, consent: consentToJson(rows, config.consentVersion) });
});

accountRoutes.put('/consent', async (c) => {
  const { auth } = await requireLiveParent(c);
  if (auth.via !== 'bearer') throw errors.notApproved('Consent changes need the parent sign-in, not a device approval.');
  const config = c.get('config');
  const body = c.get('body');
  const kind = str(body, 'kind', { required: true, max: 16 });
  if (!(CONSENT_KINDS as readonly string[]).includes(kind)) throw errors.badRequest(`kind must be one of ${CONSENT_KINDS.join(', ')}`);
  const version = intField(body, 'version', { min: 1, max: 1000, fallback: config.consentVersion });
  const granted = boolField(body, 'granted', true);
  await setConsent(c.env.DB, { parentId: auth.parentId, kind: kind as ConsentKind, version, granted, now: c.get('now') });
  const rows = await listConsent(c.env.DB, auth.parentId);
  return c.json({ parentId: auth.parentId, requiredVersion: config.consentVersion, consent: consentToJson(rows, config.consentVersion) });
});

// ----------------------------------------------------------- entitlements
accountRoutes.get('/entitlements', async (c) => {
  const { auth } = await requireLiveParent(c);
  const config = c.get('config');
  const now = c.get('now');
  const rows = await listEntitlements(c.env.DB, auth.parentId);
  const eff = effectiveEntitlement(rows, config, now);
  return c.json({
    parentId: auth.parentId,
    entitlement: eff.entitlement,
    activeUntil: eff.activeUntil,
    source: eff.source,
    allowances: { free: { dailySeconds: config.freeDailySeconds, dailyTurns: config.freeDailyTurns }, family_club: { dailySeconds: config.familyClubDailySeconds, dailyTurns: config.familyClubDailyTurns } },
    products: config.familyClubProductIds.map((productId) => ({ productId, priceHint: config.priceHint })),
    billing: { enabled: config.billingEnabled },
    records: rows.map((r) => ({ productId: r.product_id, source: r.source, status: r.status, periodEnd: r.period_end === null ? null : new Date(r.period_end).toISOString() })),
  });
});

// ---------------------------------------------------------------- progress
accountRoutes.get('/progress', async (c) => {
  const { auth } = await requireLiveParent(c);
  const childId = c.req.query('childId') || auth.childId || '';
  const child = childId ? await getChild(c.env.DB, auth.parentId, childId) : (await listChildren(c.env.DB, auth.parentId))[0];
  if (!child) throw errors.notFound('Child not found.');
  return c.json({ childId: child.id, progress: (await listProgress(c.env.DB, child.id)).map(progressToJson) });
});

accountRoutes.put('/progress', async (c) => {
  const { auth } = await requireLiveParent(c);
  const body = c.get('body');
  const childId = str(body, 'childId', { max: 64 }) || auth.childId || '';
  const child = childId ? await getChild(c.env.DB, auth.parentId, childId) : (await listChildren(c.env.DB, auth.parentId))[0];
  if (!child) throw errors.notFound('Child not found.');
  const lessonId = str(body, 'lessonId', { required: true, max: 80, re: ID_RE });
  if (!LESSONS.has(lessonId) && !c.get('config').devMode) throw errors.unknownLesson();
  const stepIndex = intField(body, 'stepIndex', { min: 0, max: 200, fallback: 0 });
  const stars = intField(body, 'stars', { min: 0, max: 100, fallback: 0 });
  const completed = boolField(body, 'completed', false);
  const row = await upsertProgress(c.env.DB, { childId: child.id, lessonId, stepIndex, completed, stars, now: c.get('now') });
  return c.json({ childId: child.id, ...progressToJson(row) });
});
