// Application wiring: middleware -> routes. `createApp` takes test hooks
// (a fake provider / fetch); production uses the registry.
import { Hono } from 'hono';
import { ApiError, errors } from './errors';
import { loadConfig, type Env } from './env';
import { TokenService } from './auth/tokens';
import { authMiddleware } from './auth/middleware';
import type { AppContext, Vars } from './auth/context';
import { FixedWindowLimiter } from './util/rate_limit';
import { uuid } from './util/crypto';
import { resolveProvider } from './tutor/provider_registry';
import type { TutorProvider } from './tutor/provider_interface';
import { accountRoutes } from './routes/accounts';
import { tutorRoutes } from './routes/tutor';
import { devRoutes } from './routes/dev';
import { billingRoutes } from './billing/index';
import { LESSONS } from './tutor/lessons';

export const API_VERSION = 'v1';

export interface AppOptions {
  provider?: TutorProvider;
  fetchImpl?: typeof fetch;
  /** Tests: bypass the isolate-wide IP limiter state. */
  limiter?: FixedWindowLimiter;
}

const sharedLimiter = new FixedWindowLimiter();

export function createApp(options: AppOptions = {}) {
  const app = new Hono<{ Bindings: Env; Variables: Vars }>();
  const limiter = options.limiter ?? sharedLimiter;

  // 1. clock, config, request id, access log (route pattern only: never the URL, ids, headers or bodies)
  app.use('*', async (c, next) => {
    const config = loadConfig(c.env);
    const debugNow = config.devMode ? Number(c.req.header('x-debug-now')) : NaN;
    const now = Number.isFinite(debugNow) && debugNow > 0 ? debugNow : Date.now();
    c.set('config', config);
    c.set('now', now);
    const requestId = c.req.header('cf-ray') || uuid();
    c.set('requestId', requestId);
    c.set('tokens', new TokenService(c.env.PARENT_TOKEN_SECRET || '', config.devMode));
    c.set('provider', options.provider ?? resolveProvider(config, c.env.OPENAI_API_KEY, options.fetchImpl));
    c.set('body', undefined);
    c.set('auth', null);
    const started = Date.now();
    await next();
    c.header('x-request-id', requestId);
    console.log(JSON.stringify({ event: 'request', requestId, method: c.req.method, route: c.req.routePath, status: c.res.status, durationMs: Date.now() - started }));
  });

  // 2. health (no auth, no rate limit)
  const health = async (c: AppContext) => {
    const config = c.get('config');
    const body: Record<string, unknown> = config.devMode
      ? { ok: true, service: 'little-days-cloud', apiVersion: API_VERSION, devMode: true, provider: config.providerName, lessons: LESSONS.size, billingEnabled: config.billingEnabled }
      : { ok: true, apiVersion: API_VERSION };
    // `?db=1`: the first-deployment check. Proves the D1 binding answers and
    // counts applied migrations. Numbers only; never a row of user data.
    if (c.req.query('db') === '1') {
      try {
        const row = await c.env.DB.prepare('SELECT COUNT(*) AS n FROM d1_migrations').first<{ n: number }>();
        body.db = { ok: true, migrations: Number(row?.n ?? 0) };
      } catch (error) {
        body.ok = false;
        body.db = { ok: false, error: 'd1_unavailable' };
        return c.json(body, 503);
      }
    }
    return c.json(body);
  };
  app.get('/healthz', health);
  app.get('/v1/health', health);
  app.get('/api/v1/health', health);

  app.get('/readyz', async (c) => {
    const config = c.get('config');
    const checks: Record<string, boolean> = { worker: true, d1: false, durableObjects: Boolean(c.env.TUTOR_SESSION && c.env.QUOTA), requiredConfig: Boolean(c.env.PARENT_TOKEN_SECRET) };
    try { await c.env.DB.prepare('SELECT 1 AS ok').first(); checks.d1 = true; } catch { checks.d1 = false; }
    const ok = Object.values(checks).every(Boolean);
    return c.json({ ok, closed: !config.productionEnabled, billingEnabled: config.billingEnabled, liveChildAudioEnabled: config.liveChildAudioEnabled, checks }, ok ? 200 : 503);
  });

  // 3. per-IP rate limit, body cap + JSON parse, parent credential
  app.use('*', async (c, next) => {
    if (c.req.path === '/healthz' || c.req.path === '/readyz' || c.req.path.endsWith('/v1/health')) return next();
    const config = c.get('config');
    const ip = c.req.header('cf-connecting-ip') || 'unknown';
    const r = limiter.hit(`ip:${ip}`, config.ipPerMinute, c.get('now'));
    if (!r.allowed) throw errors.rateLimited(r.retryAfterSeconds);
    if (c.req.method !== 'GET' && c.req.method !== 'HEAD' && c.req.method !== 'DELETE') {
      const declared = Number(c.req.header('content-length') || 0);
      if (declared > config.maxBodyBytes) throw errors.payloadTooLarge();
      const text = await c.req.text();
      if (text.length > config.maxBodyBytes) throw errors.payloadTooLarge();
      if (text.trim().length) {
        let parsed: unknown;
        try {
          parsed = JSON.parse(text);
        } catch {
          throw errors.badRequest('Body must be valid JSON.');
        }
        c.set('body', parsed);
      } else c.set('body', {});
    }
    return next();
  });
  app.use('/v1/*', authMiddleware);
  app.use('/api/v1/*', authMiddleware);

  // Closed production validates infrastructure without accepting child tutor,
  // commerce or school activation traffic. DEV_MODE remains fully testable.
  app.use('*', async (c, next) => {
    const config = c.get('config');
    if (config.devMode || config.productionEnabled) return next();
    const path = c.req.path;
    if (path.startsWith('/v1/tutor') || path.startsWith('/api/v1/tutor') || path.includes('/billing/') || path.startsWith('/v1/license') || path.startsWith('/v1/school')) {
      throw errors.providerUnavailable('Little Days online learning is not open yet.');
    }
    return next();
  });

  // 4. routes, under /v1 and (for the shipped Godot clients) /api/v1
  const api = new Hono<{ Bindings: Env; Variables: Vars }>();
  api.route('/', accountRoutes);
  api.route('/', tutorRoutes);
  // Agent F's billing module is a plain fetch-style handler (returns null off
  // its mount); it is served here under /v1/billing with the Worker env.
  api.all('/billing/*', async (c) => {
    // The auth middleware may already have read the body; hand billing a
    // fresh Request built from Hono's cached text so it can parse it again.
    const raw = c.req.raw;
    const body = raw.method === 'GET' || raw.method === 'HEAD' ? undefined : await c.req.text();
    const fresh = new Request(raw.url, { method: raw.method, headers: raw.headers, body });
    const handled = await billingRoutes(fresh, c.env as never);
    if (handled) return handled;
    throw errors.notFound();
  });
  api.use('/dev/*', async (c, next) => {
    if (!c.get('config').devMode) throw errors.notFound();
    return next();
  });
  api.route('/', devRoutes);
  app.route('/v1', api);
  app.route('/api/v1', api);

  app.notFound((c) => c.json(errors.notFound().toBody(), 404));
  app.onError((err, c) => {
    if (err instanceof ApiError) {
      if (err.code === 'rate_limited') c.header('retry-after', String(err.extra.retryAfterSeconds ?? 1));
      return c.json(err.toBody(), err.status as 400);
    }
    console.log(`[cloud] unhandled error on ${c.req.routePath}: ${err instanceof Error ? err.message : 'error'}`);
    return c.json(errors.internal().toBody(), 500);
  });

  return app;
}
