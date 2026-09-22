// HTTP surface, mounted at /v1/billing by the Worker's router (index.ts):
//
//   POST /verify               device receipt -> store check -> decision   (the app)
//   GET  /entitlement?clientId= current decision for a subject             (the app / quota)
//   POST /apple/notifications  App Store Server Notifications V2           (Apple)
//   POST /google/rtdn          Play RTDN via Pub/Sub push                  (Google)
//
// The backend owns the decision. A device never states an entitlement; it
// presents a receipt. Real stores are consulted only when BILLING_PURCHASES_ENABLED
// is "1" (the same owner switch as the app's project setting, on the server
// side); the mock store only when BILLING_DEV_MODE is "1".
import { AppleVerifier } from './apple.ts';
import { PRODUCTS, isKnownProduct, productById } from './config.ts';
import { decisionFromRow, quotaAllowanceFor } from './decision.ts';
import { processPurchaseEvent } from './events.ts';
import { GoogleVerifier } from './google.ts';
import { D1BillingRepo, type BillingRepo, type D1Like } from './repo.ts';
import { BillingError, STORES, type NormalizedTransaction, type ProcessResult, type Store } from './types.ts';

export interface BillingEnv {
  DB?: D1Like;
  BILLING_PURCHASES_ENABLED?: string;
  BILLING_DEV_MODE?: string;
  APPLE_BUNDLE_ID?: string;
  APPLE_ISSUER_ID?: string;
  APPLE_KEY_ID?: string;
  APPLE_IAP_PRIVATE_KEY_P8?: string;
  APPLE_ENVIRONMENT?: string;
  APPLE_ROOT_CA_G3_SHA256?: string;
  GOOGLE_PACKAGE_NAME?: string;
  GOOGLE_SERVICE_ACCOUNT_JSON?: string;
  GOOGLE_RTDN_TOKEN?: string;
}

export interface BillingDeps {
  repo: BillingRepo;
  now: () => number;
  apple: AppleVerifier | null;
  google: GoogleVerifier | null;
  /** Access log hook: route, status, latency only. Never bodies or ids. */
  log?: (line: { route: string; status: number; ms: number }) => void;
}

const MAX_BODY_BYTES = 32 * 1024;
const CLIENT_ID_PATTERN = /^[A-Za-z0-9._:-]{4,128}$/;

export function purchasesEnabled(env: BillingEnv): boolean {
  return env.BILLING_PURCHASES_ENABLED === '1';
}

export function devMode(env: BillingEnv): boolean {
  return env.BILLING_DEV_MODE === '1';
}

/** Builds the default deps from env. Tests pass their own. */
export function depsFromEnv(env: BillingEnv, fetchImpl: typeof fetch = fetch, now: () => number = () => Date.now()): BillingDeps {
  if (!env.DB) throw new Error('billing: DB binding missing');
  const apple = env.APPLE_BUNDLE_ID && env.APPLE_ISSUER_ID && env.APPLE_KEY_ID && env.APPLE_IAP_PRIVATE_KEY_P8
    ? new AppleVerifier({
      bundleId: env.APPLE_BUNDLE_ID,
      issuerId: env.APPLE_ISSUER_ID,
      keyId: env.APPLE_KEY_ID,
      privateKeyPem: env.APPLE_IAP_PRIVATE_KEY_P8,
      environment: env.APPLE_ENVIRONMENT === 'sandbox' ? 'sandbox' : 'production',
      trustedRootSha256Hex: env.APPLE_ROOT_CA_G3_SHA256 || undefined,
    }, { fetch: fetchImpl, now })
    : null;
  let google: GoogleVerifier | null = null;
  if (env.GOOGLE_PACKAGE_NAME && env.GOOGLE_SERVICE_ACCOUNT_JSON) {
    const account = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_JSON) as { client_email: string; private_key: string; token_uri?: string };
    google = new GoogleVerifier({ packageName: env.GOOGLE_PACKAGE_NAME, serviceAccount: account, rtdnToken: env.GOOGLE_RTDN_TOKEN }, { fetch: fetchImpl, now });
  }
  return { repo: new D1BillingRepo(env.DB), now, apple, google };
}

// -- helpers ----------------------------------------------------------------------------

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });
}

function fail(error: BillingError): Response {
  return json(error.status, { ok: false, code: error.code, message: error.message });
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const length = Number(request.headers.get('content-length') ?? '0');
  if (length > MAX_BODY_BYTES) throw new BillingError(413, 'payload_too_large');
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) throw new BillingError(413, 'payload_too_large');
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('not an object');
    return parsed as Record<string, unknown>;
  } catch {
    throw new BillingError(400, 'bad_request', 'body must be a JSON object');
  }
}

function decisionReply(result: ProcessResult, extra: Record<string, unknown> = {}): Response {
  if (result.outcome === 'conflict') return json(409, { ok: false, code: 'conflict', message: result.reason });
  if (result.outcome === 'rejected') return json(result.httpStatus, { ok: false, code: result.reason, message: result.reason });
  const decision = result.decision;
  return json(200, {
    ok: true,
    outcome: result.outcome,
    decision,
    quota: decision ? quotaAllowanceFor(decision) : null,
    ...extra,
  });
}

// -- POST /verify -------------------------------------------------------------------

export async function handleVerify(request: Request, env: BillingEnv, deps: BillingDeps): Promise<Response> {
  const body = await readJson(request);
  const store = body.store;
  const productId = body.productId;
  const transactionId = body.transactionId;
  const payload = body.payload;
  const clientId = body.clientId;
  if (typeof store !== 'string' || !STORES.includes(store as Store)) throw new BillingError(400, 'bad_request', 'store must be apple, google or mock');
  if (!isKnownProduct(productId)) throw new BillingError(400, 'unknown_product', `productId must be one of ${PRODUCTS.map((p) => p.productId).join(', ')}`);
  if (typeof transactionId !== 'string' || transactionId.length === 0 || transactionId.length > 256) throw new BillingError(400, 'bad_request', 'transactionId required');
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) throw new BillingError(400, 'bad_request', 'payload must be an object');
  if (typeof clientId !== 'string' || !CLIENT_ID_PATTERN.test(clientId)) throw new BillingError(400, 'bad_request', 'clientId required');

  const tx = await verifyWithStore(store as Store, payload as Record<string, unknown>, transactionId, env, deps);
  if (tx.productId !== productId) throw new BillingError(400, 'product_mismatch', 'the store reports a different product than the receipt claims');

  // The verified store marker must resolve to the signed-in parent account.
  // A guest installation cannot buy, and a marker issued for another parent
  // cannot be replayed against this installation.
  let subjectId = clientId;
  if (store !== 'mock') {
    if (!env.DB) throw new BillingError(503, 'store_unavailable');
    const owner = await env.DB.prepare('SELECT account_id,guest_account_id FROM installations WHERE installation_id=?').bind(clientId).first<{ account_id: string | null; guest_account_id: string | null }>();
    if (!owner?.account_id || owner.guest_account_id) throw new BillingError(403, 'parent_account_required', 'link a parent account before purchasing');
    const expected = await env.DB.prepare('SELECT mapping_value FROM purchase_identity_mappings WHERE account_id=? AND platform=?').bind(owner.account_id, store).first<{ mapping_value: string }>();
    if (!expected || !tx.accountToken || expected.mapping_value !== tx.accountToken) throw new BillingError(409, 'purchase_account_mismatch', 'the verified store account marker does not match this parent account');
    subjectId = owner.account_id;
  }

  const result = await processPurchaseEvent(deps.repo, tx, { nowMs: deps.now(), subjectId });
  // Google: acknowledge after a granting decision has been stored, never before.
  if (store === 'google' && deps.google && result.decision && (result.decision.status === 'active' || result.decision.status === 'grace') && result.outcome === 'applied') {
    const token = String((payload as Record<string, unknown>).purchaseToken ?? '');
    if (token) await deps.google.acknowledge(tx.productId, token).catch(() => false);
  }
  return decisionReply(result);
}

async function verifyWithStore(store: Store, payload: Record<string, unknown>, transactionId: string, env: BillingEnv, deps: BillingDeps): Promise<NormalizedTransaction> {
  if (store === 'mock') {
    if (!devMode(env)) throw new BillingError(403, 'mock_not_allowed', 'the mock store exists only in dev mode');
    return mockTransaction(payload, transactionId, deps.now());
  }
  // The owner switch, server side: until purchases are enabled no store API is
  // called and no real receipt can become an entitlement.
  if (!purchasesEnabled(env)) throw new BillingError(503, 'billing_disabled', 'billing is not enabled on this server');
  try {
    if (store === 'apple') {
      if (!deps.apple) throw new BillingError(503, 'store_not_configured', 'Apple credentials are not configured');
      return await deps.apple.verifyDevicePayload({ ...payload, transactionId: payload.transactionId ?? transactionId });
    }
    if (!deps.google) throw new BillingError(503, 'store_not_configured', 'Google credentials are not configured');
    return await deps.google.verifyDevicePayload(payload);
  } catch (error) {
    if (error instanceof BillingError) throw error;
    const message = (error as Error).message ?? 'verification failed';
    // Credential/connectivity trouble is the server's problem (503); a receipt
    // the store does not recognise is the caller's (400).
    const status = /credentials|api \d|token endpoint/.test(message) ? 503 : 400;
    throw new BillingError(status, status === 503 ? 'store_unavailable' : 'receipt_rejected', message);
  }
}

/** DEV ONLY: the Godot MockStoreGateway's receipt, taken at face value. */
function mockTransaction(payload: Record<string, unknown>, transactionId: string, nowMs: number): NormalizedTransaction {
  if (payload.mock !== true) throw new BillingError(400, 'receipt_rejected', 'not a mock receipt');
  const productId = String(payload.productId ?? '');
  const product = productById(productId);
  if (!product) throw new BillingError(400, 'unknown_product');
  const original = String(payload.originalTransactionId ?? transactionId);
  const expiresAtMs = typeof payload.expiresAtMs === 'number' ? payload.expiresAtMs : nowMs + product.nominalPeriodDays * 24 * 3600 * 1000;
  return {
    store: 'mock',
    productId,
    transactionId,
    originalTransactionId: original,
    purchaseTimeMs: nowMs,
    expiresAtMs,
    revokedAtMs: typeof payload.revokedAtMs === 'number' ? payload.revokedAtMs : null,
    gracePeriodExpiresAtMs: null,
    autoRenewing: true,
    environment: 'mock',
    accountToken: null,
    eventTimeMs: typeof payload.eventTimeMs === 'number' ? payload.eventTimeMs : nowMs,
    source: 'mock',
  };
}

// -- GET /entitlement ---------------------------------------------------------------

export async function handleEntitlement(request: Request, _env: BillingEnv, deps: BillingDeps): Promise<Response> {
  const clientId = new URL(request.url).searchParams.get('clientId') ?? '';
  if (!CLIENT_ID_PATTERN.test(clientId)) throw new BillingError(400, 'bad_request', 'clientId required');
  const row = await deps.repo.getEntitlement(clientId);
  const decision = decisionFromRow(row, deps.now());
  return json(200, { ok: true, decision, quota: quotaAllowanceFor(decision) });
}

// -- POST /apple/notifications ---------------------------------------------------------

export async function handleAppleNotification(request: Request, env: BillingEnv, deps: BillingDeps): Promise<Response> {
  if (!deps.apple) throw new BillingError(503, 'store_not_configured');
  const body = await readJson(request);
  let parsed: Awaited<ReturnType<AppleVerifier['parseNotification']>>;
  try {
    parsed = await deps.apple.parseNotification(body);
  } catch (error) {
    // A payload Apple did not sign is not Apple's: 401 (Apple does not retry on 4xx).
    throw new BillingError(401, 'unverified_notification', (error as Error).message);
  }
  if (!parsed.transaction) return json(200, { ok: true, outcome: 'ignored', notificationType: parsed.notificationType });
  // Notifications are applied regardless of the purchases switch: a refund
  // must always be honoured, even if verification was switched off afterwards.
  void env;
  const result = await processPurchaseEvent(deps.repo, parsed.transaction, { nowMs: deps.now(), subjectId: null });
  if (result.outcome === 'conflict') return json(409, { ok: false, code: 'conflict' });
  return json(200, { ok: true, outcome: result.outcome, notificationType: parsed.notificationType, subtype: parsed.subtype, subjects: result.subjects.length });
}

// -- POST /google/rtdn -----------------------------------------------------------------------

export async function handleGoogleRtdn(request: Request, _env: BillingEnv, deps: BillingDeps): Promise<Response> {
  if (!deps.google) throw new BillingError(503, 'store_not_configured');
  const authenticated = await deps.google.authenticatePush(new URL(request.url), request.headers.get('authorization'));
  if (!authenticated) throw new BillingError(401, 'unauthenticated_push');
  const body = await readJson(request);
  let rtdn;
  try {
    rtdn = deps.google.parseRtdn(body);
  } catch (error) {
    // Malformed / foreign messages are acked (200) so Pub/Sub stops redelivering them.
    return json(200, { ok: true, outcome: 'ignored', reason: (error as Error).message });
  }
  let tx: NormalizedTransaction | null;
  try {
    tx = await deps.google.transactionForRtdn(rtdn);
  } catch (error) {
    // The Play API was unreachable: 503 so Pub/Sub retries with backoff.
    throw new BillingError(503, 'store_unavailable', (error as Error).message);
  }
  if (!tx) return json(200, { ok: true, outcome: 'ignored', test: rtdn.test });
  const result = await processPurchaseEvent(deps.repo, tx, { nowMs: deps.now(), subjectId: null });
  if (result.outcome === 'conflict') return json(409, { ok: false, code: 'conflict' });
  return json(200, { ok: true, outcome: result.outcome, notificationType: rtdn.subscription?.name ?? (rtdn.voided ? 'VOIDED_PURCHASE' : 'UNKNOWN'), subjects: result.subjects.length });
}

// -- router -------------------------------------------------------------------------------

export const BILLING_MOUNT = '/v1/billing';

/**
 * Dispatches a request whose path starts with `/v1/billing`. Returns null for
 * paths outside the mount so the Worker's own router can carry on.
 */
export async function handleBillingRequest(request: Request, env: BillingEnv, deps: BillingDeps): Promise<Response | null> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith(BILLING_MOUNT)) return null;
  const route = url.pathname.slice(BILLING_MOUNT.length) || '/';
  const started = deps.now();
  let response: Response;
  try {
    if (request.method === 'POST' && route === '/verify') response = await handleVerify(request, env, deps);
    else if (request.method === 'GET' && route === '/entitlement') response = await handleEntitlement(request, env, deps);
    else if (request.method === 'POST' && route === '/apple/notifications') response = await handleAppleNotification(request, env, deps);
    else if (request.method === 'POST' && route === '/google/rtdn') response = await handleGoogleRtdn(request, env, deps);
    else response = json(404, { ok: false, code: 'not_found' });
  } catch (error) {
    response = error instanceof BillingError ? fail(error) : json(500, { ok: false, code: 'internal_error' });
  }
  deps.log?.({ route: `${request.method} ${BILLING_MOUNT}${route}`, status: response.status, ms: deps.now() - started });
  return response;
}
