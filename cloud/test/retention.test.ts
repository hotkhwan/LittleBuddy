import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';
import worker from '../src/index';
import { T0, createSession, lessonTurnBody, makeClient, uniqueId } from './helpers';

async function count(table: string, where: string, ...binds: unknown[]): Promise<number> {
  return Number((await env.DB.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE ${where}`).bind(...binds).first<{ n: number }>())?.n ?? 0);
}

describe('retention', () => {
  it('the purge removes this device\'s rows once they are older than RETENTION_DAYS (idempotency after 24 h), and keeps fresh ones', async () => {
    // A clock far from every other test so the purge cutoffs only ever reach this test's rows.
    const c = makeClient({ clock: { t: T0 + 3000 * 86_400_000, now() { return this.t; }, advance(s: number) { this.t += s * 1000; } } });
    const s1 = await createSession(c, { clientId: uniqueId('old') });
    expect(s1.status).toBe(201);
    const old = s1.body.sessionId;
    await c.api('POST', `/v1/tutor/sessions/${old}/turns`, lessonTurnBody(), { 'idempotency-key': 'old' });
    await c.api('POST', `/v1/tutor/sessions/${old}/end`);
    c.clock.advance(2 * 86_400);
    const s2 = await createSession(c, { childId: s1.body.childId, clientId: uniqueId('fresh') });
    const fresh = s2.body.sessionId;
    await c.api('POST', `/v1/tutor/sessions/${fresh}/turns`, lessonTurnBody(), { 'idempotency-key': 'fresh' });

    const r = await c.api('POST', '/v1/dev/retention/purge');
    expect(r.status).toBe(200);
    expect(await count('api_idempotency', 'session_id = ?', old)).toBe(0);
    expect(await count('api_idempotency', 'session_id = ?', fresh)).toBe(1);
    expect(await count('tutor_sessions', 'id IN (?, ?)', old, fresh)).toBe(2);

    c.clock.advance(31 * 86_400);
    const r2 = await c.api('POST', '/v1/dev/retention/purge');
    expect(r2.body.sessions).toBeGreaterThanOrEqual(2);
    expect(await count('tutor_sessions', 'id IN (?, ?)', old, fresh)).toBe(0);
    expect(await count('usage_events', 'session_id IN (?, ?)', old, fresh)).toBe(0);
    expect(await count('daily_quota', 'child_id = ?', s1.body.childId)).toBe(0);
    expect(await count('child_profiles', 'id = ?', s1.body.childId)).toBe(1); // profiles are not learning history
  });

  it('the scheduled handler runs the purge with the real clock', async () => {
    const id = uniqueId('ancient');
    await env.DB.prepare("INSERT INTO usage_events (id, session_id, kind, tokens_in, tokens_out, audio_seconds, cost_usd_micro, created_at) VALUES (?, 's', 'turn', 0, 0, 0, 0, ?)").bind(id, Date.now() - 400 * 86_400_000).run();
    const ctx = createExecutionContext();
    await worker.scheduled({ scheduledTime: Date.now(), cron: '17 3 * * *', noRetry() {} } as ScheduledController, env as never, ctx);
    await waitOnExecutionContext(ctx);
    expect(await count('usage_events', 'id = ?', id)).toBe(0);
  });
});
