-- Production platform schema. This migration is intentionally additive: the
-- original parent_accounts, entitlements, purchase_events and tutor accounting
-- tables remain valid while application code moves to the normalized model.
-- Timestamps are unix milliseconds. Money is integer micro-USD unless named
-- *_cents. No raw receipts, child audio, conversations or legal child names.

CREATE TABLE IF NOT EXISTS accounts (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','deleted')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER
);
CREATE INDEX IF NOT EXISTS accounts_status ON accounts(status, updated_at);

CREATE TABLE IF NOT EXISTS parents (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  auth_provider TEXT NOT NULL,
  subject_hash TEXT NOT NULL,
  email_hash TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(auth_provider, subject_hash)
);
CREATE INDEX IF NOT EXISTS parents_account ON parents(account_id);

-- Nullable bridges keep every pre-production row valid.
ALTER TABLE child_profiles ADD COLUMN account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE child_profiles ADD COLUMN owner_parent_id TEXT REFERENCES parents(id) ON DELETE SET NULL;
ALTER TABLE child_profiles ADD COLUMN age_band TEXT;
ALTER TABLE child_profiles ADD COLUMN language TEXT;
ALTER TABLE child_profiles ADD COLUMN learning_level TEXT;
CREATE INDEX IF NOT EXISTS child_profiles_account ON child_profiles(account_id);

CREATE TABLE IF NOT EXISTS plans (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('draft','active','retired')),
  policy_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS plan_features (
  plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
  feature_key TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
  config_json TEXT NOT NULL DEFAULT '{}',
  PRIMARY KEY(plan_id, feature_key)
);

-- Policy values are data, never mobile application constants. NULL means the
-- feature is unavailable or unlimited according to the policy evaluator.
ALTER TABLE plans ADD COLUMN standard_daily_seconds INTEGER CHECK(standard_daily_seconds >= 0);
ALTER TABLE plans ADD COLUMN standard_monthly_tokens INTEGER CHECK(standard_monthly_tokens >= 0);
ALTER TABLE plans ADD COLUMN live_monthly_seconds INTEGER CHECK(live_monthly_seconds >= 0);
ALTER TABLE plans ADD COLUMN live_session_max_seconds INTEGER CHECK(live_session_max_seconds >= 0);
ALTER TABLE plans ADD COLUMN provider_budget_cents_monthly INTEGER CHECK(provider_budget_cents_monthly >= 0);
ALTER TABLE plans ADD COLUMN provider_budget_cents_daily INTEGER CHECK(provider_budget_cents_daily >= 0);
ALTER TABLE plans ADD COLUMN free_trial_live_seconds_daily INTEGER CHECK(free_trial_live_seconds_daily >= 0);
ALTER TABLE plans ADD COLUMN free_trial_days INTEGER CHECK(free_trial_days >= 0);
ALTER TABLE plans ADD COLUMN child_profile_limit INTEGER CHECK(child_profile_limit >= 0);

CREATE TABLE IF NOT EXISTS subscriptions (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  plan_id TEXT NOT NULL REFERENCES plans(id),
  source TEXT NOT NULL CHECK(source IN ('apple','google','manual')),
  status TEXT NOT NULL,
  original_transaction_ref_hash TEXT,
  current_period_start INTEGER,
  current_period_end INTEGER,
  cancel_at_period_end INTEGER NOT NULL DEFAULT 0 CHECK(cancel_at_period_end IN (0,1)),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(source, original_transaction_ref_hash)
);
CREATE INDEX IF NOT EXISTS subscriptions_account_status ON subscriptions(account_id, status, current_period_end);

CREATE TABLE IF NOT EXISTS subscription_events (
  id TEXT PRIMARY KEY,
  subscription_id TEXT REFERENCES subscriptions(id) ON DELETE SET NULL,
  store TEXT NOT NULL CHECK(store IN ('apple','google','manual')),
  external_event_id TEXT NOT NULL,
  event_type TEXT NOT NULL,
  payload_hash TEXT NOT NULL,
  effective_at INTEGER,
  received_at INTEGER NOT NULL,
  processed_at INTEGER,
  UNIQUE(store, external_event_id)
);
CREATE INDEX IF NOT EXISTS subscription_events_subscription ON subscription_events(subscription_id, received_at);
CREATE INDEX IF NOT EXISTS subscription_events_unprocessed ON subscription_events(processed_at, received_at);

CREATE TABLE IF NOT EXISTS store_products (
  id TEXT PRIMARY KEY,
  plan_id TEXT NOT NULL REFERENCES plans(id),
  platform TEXT NOT NULL CHECK(platform IN ('apple','google')),
  product_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'inactive' CHECK(status IN ('inactive','active','retired')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(platform, product_id)
);
CREATE INDEX IF NOT EXISTS store_products_plan ON store_products(plan_id, platform);

CREATE TABLE IF NOT EXISTS purchase_transactions (
  id TEXT PRIMARY KEY,
  account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  subscription_id TEXT REFERENCES subscriptions(id) ON DELETE SET NULL,
  store_product_id TEXT REFERENCES store_products(id),
  platform TEXT NOT NULL CHECK(platform IN ('apple','google')),
  external_transaction_id TEXT NOT NULL,
  original_transaction_ref_hash TEXT,
  purchase_token_hash TEXT,
  state TEXT NOT NULL,
  purchased_at INTEGER,
  expires_at INTEGER,
  revoked_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(platform, external_transaction_id)
);
CREATE INDEX IF NOT EXISTS purchase_transactions_account ON purchase_transactions(account_id, created_at);
CREATE INDEX IF NOT EXISTS purchase_transactions_original ON purchase_transactions(platform, original_transaction_ref_hash);

-- Extend the legacy entitlement projection into a normalized, generic grant.
ALTER TABLE entitlements ADD COLUMN entitlement_type TEXT;
ALTER TABLE entitlements ADD COLUMN entitlement_key TEXT;
ALTER TABLE entitlements ADD COLUMN plan_id TEXT REFERENCES plans(id);
ALTER TABLE entitlements ADD COLUMN account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE entitlements ADD COLUMN child_profile_limit INTEGER;
ALTER TABLE entitlements ADD COLUMN config_json TEXT NOT NULL DEFAULT '{}';
ALTER TABLE entitlements ADD COLUMN starts_at INTEGER;
ALTER TABLE entitlements ADD COLUMN expires_at INTEGER;
CREATE INDEX IF NOT EXISTS entitlements_account_type ON entitlements(account_id, entitlement_type, status, expires_at);
CREATE INDEX IF NOT EXISTS entitlements_key ON entitlements(entitlement_key, status);

-- Canonical entitlement grants. The legacy `entitlements` table remains as a
-- compatibility projection because its original NOT NULL/primary-key shape
-- cannot safely be relaxed in an additive D1 migration.
CREATE TABLE IF NOT EXISTS entitlement_grants (
  id TEXT PRIMARY KEY,
  account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
  school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
  plan_id TEXT REFERENCES plans(id),
  entitlement_type TEXT NOT NULL,
  entitlement_key TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_id TEXT,
  status TEXT NOT NULL CHECK(status IN ('active','grace','expired','revoked')),
  starts_at INTEGER NOT NULL,
  expires_at INTEGER,
  config_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK((account_id IS NOT NULL AND school_id IS NULL) OR (account_id IS NULL AND school_id IS NOT NULL)),
  UNIQUE(source_type, source_id, entitlement_key)
);
CREATE INDEX IF NOT EXISTS entitlement_grants_account ON entitlement_grants(account_id, status, expires_at);
CREATE INDEX IF NOT EXISTS entitlement_grants_school ON entitlement_grants(school_id, status, expires_at);

CREATE TABLE IF NOT EXISTS content_entitlements (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  child_id TEXT REFERENCES child_profiles(id) ON DELETE CASCADE,
  content_key TEXT NOT NULL,
  source TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('active','expired','revoked')),
  starts_at INTEGER NOT NULL,
  expires_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS content_entitlements_unique ON content_entitlements(account_id, content_key, source);
CREATE INDEX IF NOT EXISTS content_entitlements_active ON content_entitlements(account_id, status, expires_at);

CREATE TABLE IF NOT EXISTS ai_usage_daily (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  child_id TEXT REFERENCES child_profiles(id) ON DELETE CASCADE,
  usage_day TEXT NOT NULL,
  standard_seconds INTEGER NOT NULL DEFAULT 0 CHECK(standard_seconds >= 0),
  live_seconds INTEGER NOT NULL DEFAULT 0 CHECK(live_seconds >= 0),
  text_input_tokens INTEGER NOT NULL DEFAULT 0 CHECK(text_input_tokens >= 0),
  text_output_tokens INTEGER NOT NULL DEFAULT 0 CHECK(text_output_tokens >= 0),
  estimated_provider_cost_micro_usd INTEGER NOT NULL DEFAULT 0 CHECK(estimated_provider_cost_micro_usd >= 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(account_id, child_id, usage_day)
);
CREATE INDEX IF NOT EXISTS ai_usage_daily_day ON ai_usage_daily(usage_day, account_id);

CREATE TABLE IF NOT EXISTS ai_usage_monthly (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  usage_month TEXT NOT NULL,
  standard_seconds INTEGER NOT NULL DEFAULT 0 CHECK(standard_seconds >= 0),
  live_used_seconds INTEGER NOT NULL DEFAULT 0 CHECK(live_used_seconds >= 0),
  live_allowance_seconds INTEGER NOT NULL DEFAULT 0 CHECK(live_allowance_seconds >= 0),
  text_input_tokens INTEGER NOT NULL DEFAULT 0 CHECK(text_input_tokens >= 0),
  text_output_tokens INTEGER NOT NULL DEFAULT 0 CHECK(text_output_tokens >= 0),
  estimated_provider_cost_micro_usd INTEGER NOT NULL DEFAULT 0 CHECK(estimated_provider_cost_micro_usd >= 0),
  reset_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(account_id, usage_month)
);
CREATE INDEX IF NOT EXISTS ai_usage_monthly_reset ON ai_usage_monthly(reset_at);

CREATE TABLE IF NOT EXISTS ai_sessions (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  child_id TEXT REFERENCES child_profiles(id) ON DELETE CASCADE,
  installation_id TEXT,
  tier TEXT NOT NULL,
  mode TEXT NOT NULL CHECK(mode IN ('lesson_local','standard_chat','premium_live')),
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  state TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  session_seconds INTEGER NOT NULL DEFAULT 0 CHECK(session_seconds >= 0),
  live_quota_seconds_consumed INTEGER NOT NULL DEFAULT 0 CHECK(live_quota_seconds_consumed >= 0),
  finalized_idempotency_key TEXT UNIQUE
);
CREATE INDEX IF NOT EXISTS ai_sessions_account_state ON ai_sessions(account_id, state, started_at);
CREATE INDEX IF NOT EXISTS ai_sessions_child ON ai_sessions(child_id, started_at);

CREATE TABLE IF NOT EXISTS ai_provider_usage (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES ai_sessions(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  tier TEXT NOT NULL,
  text_input_tokens INTEGER NOT NULL DEFAULT 0 CHECK(text_input_tokens >= 0),
  text_output_tokens INTEGER NOT NULL DEFAULT 0 CHECK(text_output_tokens >= 0),
  audio_input_seconds REAL NOT NULL DEFAULT 0 CHECK(audio_input_seconds >= 0),
  audio_output_seconds REAL NOT NULL DEFAULT 0 CHECK(audio_output_seconds >= 0),
  session_seconds REAL NOT NULL DEFAULT 0 CHECK(session_seconds >= 0),
  live_quota_seconds_consumed INTEGER NOT NULL DEFAULT 0 CHECK(live_quota_seconds_consumed >= 0),
  estimated_provider_cost_micro_usd INTEGER NOT NULL DEFAULT 0 CHECK(estimated_provider_cost_micro_usd >= 0),
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS ai_provider_usage_session ON ai_provider_usage(session_id, created_at);
CREATE INDEX IF NOT EXISTS ai_provider_usage_provider ON ai_provider_usage(provider, model, created_at);

CREATE TABLE IF NOT EXISTS privacy_versions (
  id TEXT PRIMARY KEY,
  document_type TEXT NOT NULL,
  version TEXT NOT NULL,
  locale TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  effective_at INTEGER NOT NULL,
  retired_at INTEGER,
  UNIQUE(document_type, version, locale)
);

CREATE TABLE IF NOT EXISTS consents (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  parent_id TEXT REFERENCES parents(id) ON DELETE SET NULL,
  privacy_version_id TEXT REFERENCES privacy_versions(id),
  consent_type TEXT NOT NULL,
  consent_version TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('granted','revoked')),
  accepted_at INTEGER,
  revoked_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS consents_account_type ON consents(account_id, consent_type, status, updated_at);

CREATE TABLE IF NOT EXISTS organizations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','suspended','closed')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS schools (
  id TEXT PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','suspended','closed')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS schools_organization ON schools(organization_id, status);

CREATE TABLE IF NOT EXISTS school_users (
  id TEXT PRIMARY KEY,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  role TEXT NOT NULL CHECK(role IN ('owner','admin','teacher')),
  status TEXT NOT NULL DEFAULT 'active',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(school_id, account_id)
);

CREATE TABLE IF NOT EXISTS school_classes (
  id TEXT PRIMARY KEY,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS school_classes_school ON school_classes(school_id, status);

CREATE TABLE IF NOT EXISTS school_students (
  id TEXT PRIMARY KEY,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  class_id TEXT REFERENCES school_classes(id) ON DELETE SET NULL,
  child_profile_id TEXT REFERENCES child_profiles(id) ON DELETE SET NULL,
  display_nickname TEXT NOT NULL,
  age_band TEXT,
  language TEXT,
  learning_level TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS school_students_class ON school_students(class_id, status);
CREATE INDEX IF NOT EXISTS school_students_school ON school_students(school_id, status);

CREATE TABLE IF NOT EXISTS licenses (
  id TEXT PRIMARY KEY,
  school_id TEXT NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
  entitlement_type TEXT NOT NULL CHECK(entitlement_type IN ('SCHOOL_STANDARD','SCHOOL_AI','SCHOOL_PREMIUM')),
  license_model TEXT NOT NULL CHECK(license_model IN ('per_seat','per_device','pooled')),
  status TEXT NOT NULL CHECK(status IN ('draft','pending','active','suspended','expired','revoked')),
  activation_code_hash TEXT UNIQUE,
  qr_token_hash TEXT UNIQUE,
  valid_from INTEGER NOT NULL,
  valid_until INTEGER NOT NULL,
  seat_count INTEGER NOT NULL DEFAULT 0 CHECK(seat_count >= 0),
  device_limit INTEGER NOT NULL DEFAULT 0 CHECK(device_limit >= 0),
  standard_ai_pool_seconds INTEGER NOT NULL DEFAULT 0 CHECK(standard_ai_pool_seconds >= 0),
  premium_live_pool_seconds INTEGER NOT NULL DEFAULT 0 CHECK(premium_live_pool_seconds >= 0),
  standard_ai_used_seconds INTEGER NOT NULL DEFAULT 0 CHECK(standard_ai_used_seconds >= 0),
  premium_live_used_seconds INTEGER NOT NULL DEFAULT 0 CHECK(premium_live_used_seconds >= 0),
  feature_flags_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK(valid_until > valid_from)
);
CREATE INDEX IF NOT EXISTS licenses_school_status ON licenses(school_id, status, valid_until);

CREATE TABLE IF NOT EXISTS license_seats (
  id TEXT PRIMARY KEY,
  license_id TEXT NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
  school_student_id TEXT REFERENCES school_students(id) ON DELETE SET NULL,
  assigned_at INTEGER NOT NULL,
  released_at INTEGER
);
CREATE UNIQUE INDEX IF NOT EXISTS license_seats_active_student ON license_seats(license_id, school_student_id) WHERE released_at IS NULL;
CREATE INDEX IF NOT EXISTS license_seats_active ON license_seats(license_id, released_at);

CREATE TABLE IF NOT EXISTS device_activations (
  id TEXT PRIMARY KEY,
  license_id TEXT NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
  account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  installation_id_hash TEXT NOT NULL,
  seat_key_hash TEXT NOT NULL,
  activation_mode TEXT NOT NULL DEFAULT 'installation' CHECK(activation_mode IN ('installation','managed_device')),
  managed_device_id_hash TEXT,
  activation_idempotency_key TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK(status IN ('active','deactivated','revoked')),
  activated_at INTEGER NOT NULL,
  deactivated_at INTEGER,
  last_seen_at INTEGER NOT NULL,
  UNIQUE(license_id, installation_id_hash)
);
CREATE INDEX IF NOT EXISTS device_activations_license ON device_activations(license_id, status);
CREATE INDEX IF NOT EXISTS device_activations_account ON device_activations(account_id, status);

CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,
  account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  organization_id TEXT REFERENCES organizations(id) ON DELETE SET NULL,
  actor_type TEXT NOT NULL,
  actor_ref_hash TEXT,
  event_type TEXT NOT NULL,
  target_type TEXT,
  target_id TEXT,
  request_id TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS audit_logs_account ON audit_logs(account_id, created_at);
CREATE INDEX IF NOT EXISTS audit_logs_organization ON audit_logs(organization_id, created_at);
CREATE INDEX IF NOT EXISTS audit_logs_event ON audit_logs(event_type, created_at);
