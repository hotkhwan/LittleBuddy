import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

const TABLES = ['parent_accounts', 'child_profiles', 'devices', 'consent_status', 'entitlements', 'purchase_events', 'tutor_sessions', 'daily_quota', 'usage_events', 'learning_progress', 'api_idempotency'];

describe('D1 migrations', () => {
  it('apply cleanly and create every table', async () => {
    const rows = (await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all<{ name: string }>()).results.map((r) => r.name);
    for (const t of TABLES) expect(rows, t).toContain(t);
  });

  it('record themselves in d1_migrations (four files)', async () => {
    const rows = (await env.DB.prepare('SELECT name FROM d1_migrations ORDER BY id').all<{ name: string }>()).results.map((r) => r.name);
    expect(rows).toEqual(['0001_accounts.sql', '0002_entitlements_billing.sql', '0003_tutor.sql', '0004_progress.sql']);
  });

  it('create the indexes retention and lookups rely on', async () => {
    const idx = (await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'index'").all<{ name: string }>()).results.map((r) => r.name);
    for (const name of ['parent_accounts_subject', 'tutor_sessions_child', 'tutor_sessions_started', 'usage_events_created', 'api_idempotency_created', 'daily_quota_day', 'entitlements_active', 'purchase_events_parent']) expect(idx, name).toContain(name);
  });

  it('purchase_events.transaction_id is UNIQUE (store replays are idempotent) - stub for Agent F to extend', async () => {
    const ins = (id: string) => env.DB.prepare('INSERT INTO purchase_events (id, store, transaction_id, product_id, parent_id, status, payload_hash, processed_at) VALUES (?, ?, ?, ?, NULL, ?, ?, ?)')
      .bind(id, 'apple', 'txn-1', 'little_days.family_club.monthly', 'received', 'deadbeef', 1).run();
    await ins('evt-1');
    await expect(ins('evt-2')).rejects.toThrow(/UNIQUE/);
    const n = await env.DB.prepare("SELECT COUNT(*) AS n FROM purchase_events WHERE transaction_id = 'txn-1'").first<{ n: number }>();
    expect(n?.n).toBe(1);
  });

  it('api_idempotency.key is the primary key', async () => {
    const ins = () => env.DB.prepare('INSERT INTO api_idempotency (key, session_id, request_hash, response_hash, status, response_json, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)').bind('k1', 's1', 'r', 'h', 200, '{}', 1).run();
    await ins();
    await expect(ins()).rejects.toThrow(/UNIQUE|PRIMARY/);
  });

  it('deleting a child cascades to progress and daily_quota', async () => {
    await env.DB.prepare("INSERT INTO parent_accounts (id, provider, subject_hash, consent_version, created_at, updated_at) VALUES ('p1', 'dev', 'h', 0, 1, 1)").run();
    await env.DB.prepare("INSERT INTO child_profiles (id, parent_id, nickname, locale, created_at, updated_at) VALUES ('c1', 'p1', 'Bud', 'en-US', 1, 1)").run();
    await env.DB.prepare("INSERT INTO learning_progress (child_id, lesson_id, step_index, stars, updated_at) VALUES ('c1', 'l1', 1, 1, 1)").run();
    await env.DB.prepare("INSERT INTO daily_quota (child_id, day_utc, seconds_used, turns_used, allowance_seconds, updated_at) VALUES ('c1', '2027-01-10', 5, 1, 300, 1)").run();
    await env.DB.prepare("DELETE FROM child_profiles WHERE id = 'c1'").run();
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM learning_progress WHERE child_id = 'c1'").first<{ n: number }>())?.n).toBe(0);
    expect((await env.DB.prepare("SELECT COUNT(*) AS n FROM daily_quota WHERE child_id = 'c1'").first<{ n: number }>())?.n).toBe(0);
  });

  it('usage_events has only numeric measurement columns (no text beyond ids)', async () => {
    const cols = (await env.DB.prepare('PRAGMA table_info(usage_events)').all<{ name: string; type: string }>()).results;
    const textCols = cols.filter((c) => c.type.toUpperCase() === 'TEXT').map((c) => c.name);
    expect(textCols.sort()).toEqual(['id', 'kind', 'session_id']);
  });
});
