// Parents, children, devices, consent, entitlements, progress.
import { Hono } from 'hono';
import { DEV_PARENT_ID, type Env } from '../env';
import { requireAuth, type Vars } from '../auth/context';
import { errors } from '../errors';
import { hmacHex } from '../util/crypto';
import { ID_RE, boolField, intField, str } from '../util/validate';
import { getParent, upsertParent } from '../db/parents';
import { childToJson, createChild, getChild, listChildren } from '../db/children';
import { PLATFORMS, listDevices, upsertDevice } from '../db/devices';
import { CONSENT_KINDS, consentToJson, listConsent, setConsent, type ConsentKind } from '../db/consent';
import { effectiveEntitlement, listEntitlements } from '../db/entitlements';
import { listProgress, progressToJson, upsertProgress } from '../db/progress';
import { LESSONS } from '../tutor/lessons';

export const accountRoutes = new Hono<{ Bindings: Env; Variables: Vars }>();

const NICKNAME_RE = /^[\p{L}\p{N} '._-]{1,24}$/u;
const BUCKET_RE = /^\d{4}-\d{4}$/;
const LOCALE_RE = /^[a-z]{2,3}(-[A-Za-z]{2,4})?$/;
const SEMVER_RE = /^[0-9A-Za-z.+-]{1,32}$/;
const MAX_CHILDREN = 6; // the DEV_MODE literal parent is exempt so local test runs can mint a child per session

// ---------------------------------------------------------------- parents
// Sign-in placeholder. `dev` works in DEV_MODE only; `apple` / `google`
// identity-token verification is the follow-up and answers 501 until then.
accountRoutes.post('/parents', async (c) => {
  const config = c.get('config');
  const now = c.get('now');
  const body = c.get('body');
  const tokens = c.get('tokens');
  const provider = str(body, 'provider', { required: true, max: 16 });
  if (provider === 'apple' || provider === 'google') throw errors.notImplemented(`${provider} sign-in is not wired yet; identity-token verification is the follow-up.`);
  if (provider !== 'dev') throw errors.badRequest('provider must be dev, apple or google');
  if (!config.devMode) throw errors.notImplemented('dev sign-in is disabled outside DEV_MODE');
  if (!tokens.configured) throw errors.providerUnavailable('PARENT_TOKEN_SECRET is not configured on this server.');
  const subject = str(body, 'subject', { required: true, max: 128, re: ID_RE });
  const clientId = str(body, 'clientId', { max: 128, re: ID_RE });
  const subjectHash = await hmacHex(c.env.PARENT_TOKEN_SECRET!, 'subject', `dev\n${subject}`);
  const { parent, created } = await upsertParent(c.env.DB, { provider: 'dev', subjectHash, now });
  const parentToken = await tokens.mintParent(parent.id, now, config.parentTokenTtlSeconds);
  const out: Record<string, unknown> = {
    parentId: parent.id,
    created,
    parentToken,
    expiresAt: new Date(now + config.parentTokenTtlSeconds * 1000).toISOString(),
    devMode: true,
  };
  if (clientId) out.parentApprovalToken = await tokens.mintApproval({ clientId, parentId: parent.id }, now, config.parentTokenTtlSeconds);
  return c.json(out, 201);
});

accountRoutes.get('/parents/me', async (c) => {
  const auth = requireAuth(c);
  const parent = await getParent(c.env.DB, auth.parentId);
  if (!parent) throw errors.notFound('Parent not found.');
  return c.json({ parentId: parent.id, provider: parent.provider, consentVersion: parent.consent_version, createdAt: new Date(parent.created_at).toISOString(), via: auth.via });
});

// The server half of the parental gate: a signed-in parent binds approval to a device (and optionally a child).
accountRoutes.post('/parents/approval', async (c) => {
  const auth = requireAuth(c);
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

// --------------------------------------------------------------- children
accountRoutes.get('/children', async (c) => {
  const auth = requireAuth(c);
  return c.json({ children: (await listChildren(c.env.DB, auth.parentId)).map(childToJson) });
});

accountRoutes.post('/children', async (c) => {
  const auth = requireAuth(c);
  const body = c.get('body');
  const nickname = str(body, 'nickname', { required: true, max: 24 }).trim();
  if (!NICKNAME_RE.test(nickname)) throw errors.badRequest('nickname must be 1-24 letters, digits or spaces');
  if (/@|https?:|www\./i.test(nickname)) throw errors.badRequest('nickname must not contain contact details');
  const avatarId = str(body, 'avatarId', { max: 40, re: ID_RE });
  const birthYearBucket = str(body, 'birthYearBucket', { max: 9, re: BUCKET_RE });
  const locale = str(body, 'locale', { max: 8, re: LOCALE_RE });
  const existing = await listChildren(c.env.DB, auth.parentId);
  if (existing.length >= MAX_CHILDREN && !(c.get('config').devMode && auth.parentId === DEV_PARENT_ID)) throw errors.badRequest(`a family can have at most ${MAX_CHILDREN} child profiles`);
  const child = await createChild(c.env.DB, { parentId: auth.parentId, nickname, avatarId: avatarId || undefined, birthYearBucket: birthYearBucket || undefined, locale: locale || undefined, now: c.get('now') });
  return c.json(childToJson(child), 201);
});

// ---------------------------------------------------------------- devices
accountRoutes.get('/devices', async (c) => {
  const auth = requireAuth(c);
  const rows = await listDevices(c.env.DB, auth.parentId);
  return c.json({ devices: rows.map((d) => ({ deviceId: d.id, platform: d.platform, appVersion: d.app_version, createdAt: new Date(d.created_at).toISOString(), lastSeenAt: new Date(d.last_seen_at).toISOString() })) });
});

accountRoutes.post('/devices', async (c) => {
  const auth = requireAuth(c);
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
  const auth = requireAuth(c);
  const config = c.get('config');
  const rows = await listConsent(c.env.DB, auth.parentId);
  return c.json({ parentId: auth.parentId, requiredVersion: config.consentVersion, consent: consentToJson(rows, config.consentVersion) });
});

accountRoutes.put('/consent', async (c) => {
  const auth = requireAuth(c);
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
  const auth = requireAuth(c);
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
  const auth = requireAuth(c);
  const childId = c.req.query('childId') || auth.childId || '';
  const child = childId ? await getChild(c.env.DB, auth.parentId, childId) : (await listChildren(c.env.DB, auth.parentId))[0];
  if (!child) throw errors.notFound('Child not found.');
  return c.json({ childId: child.id, progress: (await listProgress(c.env.DB, child.id)).map(progressToJson) });
});

accountRoutes.put('/progress', async (c) => {
  const auth = requireAuth(c);
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
