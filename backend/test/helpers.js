// Shared test helpers: an app + real HTTP server on an ephemeral port, a fake
// clock, and a temp DATA_DIR per test so persistence is exercised for real.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { loadConfig } from '../src/config.js';
import { createApp } from '../src/app.js';
import { createHttpServer } from '../src/server.js';
import { fileURLToPath } from 'node:url';

export const FIXTURE_LESSONS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), 'fixtures', 'lessons');

export const DEV_TOKEN = 'dev-parent-approval';
export const T0 = Date.UTC(2026, 8, 20, 10, 0, 0); // 2026-09-20T10:00:00Z

export function makeClock(start = T0) {
  const clock = { t: start, now: () => clock.t, advance: (s) => { clock.t += s * 1000; } };
  return clock;
}

export function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'tutor-backend-'));
}

/**
 * @param {{env?: Record<string,string>, clock?: ReturnType<typeof makeClock>, dataDir?: string, provider?: any, fetchImpl?: any}} [opts]
 */
export async function startServer(opts = {}) {
  const dataDir = opts.dataDir ?? tempDir();
  const clock = opts.clock ?? makeClock();
  // Keep legacy pricing assertions deterministic while production defaults can
  // advance independently to the configured Standard provider model.
  const env = { DEV_MODE: '1', DATA_DIR: dataDir, PARENT_APPROVAL_SECRET: 'test-secret', LESSONS_DIR: FIXTURE_LESSONS_DIR, TUTOR_MODEL: 'gpt-4o-mini', ...(opts.env ?? {}) };
  const config = loadConfig(env);
  const app = createApp({ config, now: clock.now, provider: opts.provider, fetchImpl: opts.fetchImpl, persist: true });
  const server = createHttpServer({ app });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = /** @type {import('node:net').AddressInfo} */ (server.address());
  const base = `http://127.0.0.1:${port}`;

  /**
   * Session routes need the parent token that created the session; the dev
   * token is sent by default. Pass `{'x-parent-approval': ''}` to omit it.
   * @param {string} method @param {string} p @param {any} [body] @param {Record<string,string>} [headers]
   */
  async function api(method, p, body, headers = {}) {
    const h = { 'content-type': 'application/json', 'x-parent-approval': DEV_TOKEN, ...headers };
    if (!h['x-parent-approval']) delete h['x-parent-approval'];
    const res = await fetch(base + p, {
      method,
      headers: h,
      body: body === undefined ? undefined : typeof body === 'string' ? body : JSON.stringify(body),
    });
    const text = await res.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch { json = { raw: text }; }
    return { status: res.status, body: json, headers: res.headers };
  }

  async function close() {
    await new Promise((resolve) => server.close(resolve));
  }

  return { app, server, base, api, close, dataDir, clock, config };
}

/** Create a session with the dev token. */
export async function createSession(api, { clientId = 'client-a', lessonId = 'fruits_1', token = DEV_TOKEN } = {}) {
  return api('POST', '/api/v1/tutor/sessions', { lessonId, clientId, parentApprovalToken: token }, { 'x-parent-approval': token });
}

/** A turn for the unknown lesson `fruits_1` (DEV_MODE client-context path). */
export function turnBody(overrides = {}) {
  return {
    transcript: 'apple',
    lessonContext: { stepId: 's1', outcome: 'correct', expectedAnswers: ['apple'], nextQuestionText: 'What color is the banana?', visualAssetId: 'apple_red' },
    ...overrides,
  };
}

/** A turn for the fixture lesson `colors_red_blue` (server-resolved path). */
export function lessonTurnBody(overrides = {}) {
  return {
    transcript: 'red',
    lessonContext: { stepId: 's02_red', outcome: 'correct', matched: 'red' },
    ...overrides,
  };
}
