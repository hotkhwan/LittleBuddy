// Shared test helpers: the app driven in-process with a fake clock
// (X-Debug-Now, honoured in DEV_MODE only), a fresh per-client IP limiter and
// a family sign-in that grants consent so the tutor routes are reachable.
import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test';
import { createApp, type AppOptions } from '../src/app';
import type { Env } from '../src/env';
import { FixedWindowLimiter } from '../src/util/rate_limit';

export const DEV_TOKEN = 'dev-parent-approval';
// A date in the future so the Durable Objects' real-clock alarms never fire in
// the middle of a test (ticks are driven explicitly).
export const T0 = Date.UTC(2027, 0, 10, 10, 0, 0); // 2027-01-10T10:00:00Z

export interface Clock { t: number; now: () => number; advance: (seconds: number) => void }
export function makeClock(start = T0): Clock {
  const clock: Clock = { t: start, now: () => clock.t, advance: (s) => { clock.t += s * 1000; } };
  return clock;
}

export interface ApiResponse { status: number; body: any; headers: Headers }

export interface Client {
  api: (method: string, path: string, body?: unknown, headers?: Record<string, string>) => Promise<ApiResponse>;
  clock: Clock;
  env: Env;
}

export function makeClient(opts: { clock?: Clock; env?: Partial<Env>; app?: AppOptions; ip?: string; defaultToken?: string | null } = {}): Client {
  const clock = opts.clock ?? makeClock();
  const app = createApp({ limiter: new FixedWindowLimiter(), ...(opts.app ?? {}) });
  const mergedEnv = { ...(env as unknown as Env), ...(opts.env ?? {}) } as Env;
  const ip = opts.ip ?? `10.0.${Math.floor(Math.random() * 250)}.${Math.floor(Math.random() * 250)}`;
  const defaultToken = opts.defaultToken === undefined ? DEV_TOKEN : opts.defaultToken;

  async function api(method: string, path: string, body?: unknown, headers: Record<string, string> = {}): Promise<ApiResponse> {
    const h: Record<string, string> = { 'content-type': 'application/json', 'x-debug-now': String(clock.now()), 'cf-connecting-ip': ip };
    if (defaultToken) h['x-parent-approval'] = defaultToken;
    for (const [k, v] of Object.entries(headers)) {
      if (v === '') delete h[k.toLowerCase()];
      else h[k.toLowerCase()] = v;
    }
    const init: RequestInit = { method, headers: h };
    if (body !== undefined) init.body = typeof body === 'string' ? body : JSON.stringify(body);
    const ctx = createExecutionContext();
    const res = await app.fetch(new Request(`https://cloud.test${path}`, init), mergedEnv, ctx);
    await waitOnExecutionContext(ctx);
    const text = await res.text();
    let json: unknown = null;
    try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
    return { status: res.status, body: json, headers: res.headers };
  }
  return { api, clock, env: mergedEnv };
}

export interface Family { parentId: string; parentToken: string; approvalToken: string; clientId: string; bearer: Record<string, string> }

/** Dev sign-in + all consents granted + approval bound to `clientId`. */
export async function signInFamily(client: Client, subject: string, clientId = `device-${subject}`, consent: string[] = ['privacy', 'ai_tutor', 'voice']): Promise<Family> {
  const r = await client.api('POST', '/v1/parents', { provider: 'dev', subject, clientId }, { 'x-parent-approval': '' });
  if (r.status !== 201) throw new Error(`sign-in failed: ${r.status} ${JSON.stringify(r.body)}`);
  const bearer = { authorization: `Bearer ${r.body.parentToken}`, 'x-parent-approval': '' };
  for (const kind of consent) {
    const c = await client.api('PUT', '/v1/consent', { kind, granted: true }, bearer);
    if (c.status !== 200) throw new Error(`consent failed: ${c.status} ${JSON.stringify(c.body)}`);
  }
  return { parentId: r.body.parentId, parentToken: r.body.parentToken, approvalToken: r.body.parentApprovalToken, clientId, bearer };
}

let uniq = 0;
export function uniqueId(prefix: string): string {
  uniq += 1;
  return `${prefix}-${Date.now().toString(36)}-${uniq}`;
}

/**
 * Storage is shared across tests in this pool version, so a session gets its
 * OWN child profile unless `childId` is given (`fresh: false` keeps the
 * parent's default child, which is what the shipped Godot client does).
 */
export async function createSession(client: Client, o: { clientId?: string; lessonId?: string; token?: string; childId?: string; fresh?: boolean } = {}): Promise<ApiResponse> {
  const token = o.token ?? DEV_TOKEN;
  const headers = { 'x-parent-approval': token };
  let childId = o.childId;
  if (!childId && o.fresh !== false) {
    const kid = await client.api('POST', '/v1/children', { nickname: 'Test Kid' }, headers);
    if (kid.status !== 201) throw new Error(`child create failed: ${kid.status} ${JSON.stringify(kid.body)}`);
    childId = kid.body.childId as string;
  }
  const body: Record<string, unknown> = { lessonId: o.lessonId ?? 'colors_red_blue', clientId: o.clientId ?? uniqueId('client'), parentApprovalToken: token };
  if (childId) body.childId = childId;
  return client.api('POST', '/v1/tutor/sessions', body, headers);
}

/** A fresh family with its own client (default credential = its approval token). */
export async function familyClient(subject: string, opts: Parameters<typeof makeClient>[0] = {}): Promise<{ c: Client; fam: Family; h: Record<string, string> }> {
  const clientId = uniqueId(`dev-${subject}`);
  const boot = makeClient({ ...opts, defaultToken: null });
  const fam = await signInFamily(boot, uniqueId(subject), clientId);
  const c = makeClient({ ...opts, clock: boot.clock, defaultToken: fam.approvalToken });
  return { c, fam, h: { 'x-parent-approval': fam.approvalToken } };
}

/** A turn for the bundled lesson `colors_red_blue` (server-resolved context). */
export function lessonTurnBody(overrides: Record<string, unknown> = {}) {
  return { transcript: 'red', lessonContext: { stepId: 's02_red', outcome: 'correct', matched: 'red' }, ...overrides };
}

/** A turn for an unknown lesson (DEV_MODE client-context path). */
export function devTurnBody(overrides: Record<string, unknown> = {}) {
  return { transcript: 'apple', lessonContext: { stepId: 's1', outcome: 'correct', expectedAnswers: ['apple'], nextQuestionText: 'What color is the banana?', visualAssetId: 'apple_red' }, ...overrides };
}

export function sessionStub(sessionId: string) {
  return env.TUTOR_SESSION.get(env.TUTOR_SESSION.idFromName(sessionId));
}
