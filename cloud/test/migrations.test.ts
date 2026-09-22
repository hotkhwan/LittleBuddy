import { env } from 'cloudflare:test';
import { describe, expect, it } from 'vitest';

const TABLES = [
  'parent_accounts', 'child_profiles', 'devices', 'consent_status', 'entitlements',
  'purchase_events', 'tutor_sessions', 'daily_quota', 'usage_events',
  'learning_progress', 'api_idempotency', 'accounts', 'parents', 'plans',
  'plan_features', 'subscriptions', 'subscription_events', 'store_products',
  'purchase_transactions', 'entitlement_grants', 'content_entitlements', 'ai_usage_daily',
  'ai_usage_monthly', 'ai_sessions', 'ai_provider_usage', 'privacy_versions',
  'consents', 'organizations', 'schools', 'school_users', 'school_classes',
  'school_students', 'licenses', 'license_seats', 'device_activations', 'audit_logs',
  'guest_accounts', 'identity_providers', 'parent_profiles', 'installations',
  'guest_learning_progress', 'account_learning_progress', 'guest_reward_awards',
  'account_reward_awards', 'guest_unlocks', 'account_unlocks', 'guest_settings',
  'account_settings', 'guest_ai_usage', 'account_ai_usage', 'account_ai_usage_imports',
  'account_trials', 'purchase_identity_mappings', 'friend_invites', 'friendships',
  'house_visits', 'multiplayer_sessions', 'session_members',
];

describe('D1 migrations', () => {
  it('apply cleanly and create every table', async () => {
    const rows = (await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all<{ name: string }>()).results.map((r) => r.name);
    for (const t of TABLES) expect(rows, t).toContain(t);
  });

  it('record themselves in d1_migrations', async () => {
    const rows = (await env.DB.prepare('SELECT name FROM d1_migrations ORDER BY id').all<{ name: string }>()).results.map((r) => r.name);
    expect(rows).toEqual(['0001_accounts.sql', '0002_entitlements_billing.sql', '0003_tutor.sql', '0004_progress.sql', '0005_account_privacy.sql', '0006_production_platform.sql', '0007_guest_identity.sql']);
  });

  it('enforces subscription event and purchase transaction idempotency', async () => {
    await env.DB.prepare("INSERT INTO subscription_events (id, store, external_event_id, event_type, payload_hash, received_at) VALUES ('se1','apple','notification-1','renewed','hash',1)").run();
    await expect(env.DB.prepare("INSERT INTO subscription_events (id, store, external_event_id, event_type, payload_hash, received_at) VALUES ('se2','apple','notification-1','renewed','hash',2)").run()).rejects.toThrow(/UNIQUE/);
    await env.DB.prepare("INSERT INTO purchase_transactions (id, platform, external_transaction_id, state, created_at, updated_at) VALUES ('pt1','google','order-1','purchased',1,1)").run();
    await expect(env.DB.prepare("INSERT INTO purchase_transactions (id, platform, external_transaction_id, state, created_at, updated_at) VALUES ('pt2','google','order-1','purchased',1,1)").run()).rejects.toThrow(/UNIQUE/);
  });

  it('rejects negative AI consumption and invalid license periods', async () => {
    await env.DB.prepare("INSERT INTO accounts (id, created_at, updated_at) VALUES ('acct-schema',1,1)").run();
    await expect(env.DB.prepare("INSERT INTO ai_usage_monthly (account_id, usage_month, live_used_seconds, live_allowance_seconds, reset_at, updated_at) VALUES ('acct-schema','2027-01',-1,300,2,1)").run()).rejects.toThrow(/CHECK/);
    await env.DB.prepare("INSERT INTO organizations (id,name,created_at,updated_at) VALUES ('org-schema','School Group',1,1)").run();
    await env.DB.prepare("INSERT INTO schools (id,organization_id,name,created_at,updated_at) VALUES ('school-schema','org-schema','School',1,1)").run();
    await expect(env.DB.prepare("INSERT INTO licenses (id,school_id,entitlement_type,license_model,status,valid_from,valid_until,created_at,updated_at) VALUES ('lic-schema','school-schema','SCHOOL_AI','pooled','active',10,5,1,1)").run()).rejects.toThrow(/CHECK/);
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
