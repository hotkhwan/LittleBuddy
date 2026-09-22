-- Backend-owned guest/parent identity. Installation IDs are random app UUIDs,
-- never hardware identifiers. This migration enables identity and future
-- social storage only; billing and multiplayer remain disabled by policy.
CREATE TABLE IF NOT EXISTS guest_accounts (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','linking','linked','suspended','deleted')),
  merged_into TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  linked_at INTEGER
);

CREATE TABLE IF NOT EXISTS identity_providers (
  provider TEXT NOT NULL CHECK(provider IN ('apple','google')),
  provider_subject_hash TEXT NOT NULL,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  PRIMARY KEY(provider, provider_subject_hash)
);
CREATE INDEX IF NOT EXISTS identity_providers_account ON identity_providers(account_id);

CREATE TABLE IF NOT EXISTS parent_profiles (
  id TEXT PRIMARY KEY,
  account_id TEXT NOT NULL UNIQUE REFERENCES accounts(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS installations (
  installation_id TEXT PRIMARY KEY,
  platform TEXT NOT NULL CHECK(platform IN ('ios','android','macos','windows','linux','web','unknown')),
  account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
  guest_account_id TEXT REFERENCES guest_accounts(id) ON DELETE SET NULL,
  app_version TEXT,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','replaced','revoked')),
  CHECK(account_id IS NULL OR guest_account_id IS NULL)
);
CREATE INDEX IF NOT EXISTS installations_account ON installations(account_id, status);
CREATE INDEX IF NOT EXISTS installations_guest ON installations(guest_account_id, status);

CREATE TABLE IF NOT EXISTS guest_learning_progress (
  guest_account_id TEXT NOT NULL REFERENCES guest_accounts(id) ON DELETE CASCADE,
  lesson_id TEXT NOT NULL,
  mastery REAL NOT NULL DEFAULT 0 CHECK(mastery >= 0 AND mastery <= 1),
  evidence_at INTEGER NOT NULL,
  completed_at INTEGER,
  stars INTEGER NOT NULL DEFAULT 0 CHECK(stars >= 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(guest_account_id, lesson_id)
);
CREATE TABLE IF NOT EXISTS account_learning_progress (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  lesson_id TEXT NOT NULL,
  mastery REAL NOT NULL DEFAULT 0 CHECK(mastery >= 0 AND mastery <= 1),
  evidence_at INTEGER NOT NULL,
  completed_at INTEGER,
  stars INTEGER NOT NULL DEFAULT 0 CHECK(stars >= 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(account_id, lesson_id)
);
CREATE TABLE IF NOT EXISTS guest_reward_awards (
  guest_account_id TEXT NOT NULL REFERENCES guest_accounts(id) ON DELETE CASCADE,
  award_id TEXT NOT NULL,
  reward_key TEXT NOT NULL,
  awarded_at INTEGER NOT NULL,
  PRIMARY KEY(guest_account_id, award_id)
);
CREATE TABLE IF NOT EXISTS account_reward_awards (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  award_id TEXT NOT NULL,
  reward_key TEXT NOT NULL,
  awarded_at INTEGER NOT NULL,
  PRIMARY KEY(account_id, award_id)
);
CREATE TABLE IF NOT EXISTS guest_unlocks (guest_account_id TEXT NOT NULL REFERENCES guest_accounts(id) ON DELETE CASCADE, unlock_key TEXT NOT NULL, unlocked_at INTEGER NOT NULL, PRIMARY KEY(guest_account_id, unlock_key));
CREATE TABLE IF NOT EXISTS account_unlocks (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, unlock_key TEXT NOT NULL, unlocked_at INTEGER NOT NULL, PRIMARY KEY(account_id, unlock_key));
CREATE TABLE IF NOT EXISTS guest_settings (guest_account_id TEXT NOT NULL REFERENCES guest_accounts(id) ON DELETE CASCADE, setting_key TEXT NOT NULL, value_json TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(guest_account_id, setting_key));
CREATE TABLE IF NOT EXISTS account_settings (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, setting_key TEXT NOT NULL, value_json TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY(account_id, setting_key));
CREATE TABLE IF NOT EXISTS guest_ai_usage (guest_account_id TEXT NOT NULL REFERENCES guest_accounts(id) ON DELETE CASCADE, usage_period TEXT NOT NULL, standard_seconds INTEGER NOT NULL DEFAULT 0 CHECK(standard_seconds >= 0), input_tokens INTEGER NOT NULL DEFAULT 0 CHECK(input_tokens >= 0), output_tokens INTEGER NOT NULL DEFAULT 0 CHECK(output_tokens >= 0), updated_at INTEGER NOT NULL, PRIMARY KEY(guest_account_id, usage_period));
CREATE TABLE IF NOT EXISTS account_ai_usage (account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, usage_period TEXT NOT NULL, standard_seconds INTEGER NOT NULL DEFAULT 0 CHECK(standard_seconds >= 0), input_tokens INTEGER NOT NULL DEFAULT 0 CHECK(input_tokens >= 0), output_tokens INTEGER NOT NULL DEFAULT 0 CHECK(output_tokens >= 0), updated_at INTEGER NOT NULL, PRIMARY KEY(account_id, usage_period));

CREATE TABLE IF NOT EXISTS account_trials (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  trial_key TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('eligible','active','consumed','expired')),
  started_at INTEGER,
  expires_at INTEGER,
  consumed_at INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(account_id, trial_key)
);
CREATE TABLE IF NOT EXISTS purchase_identity_mappings (
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK(platform IN ('apple','google')),
  mapping_value TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(account_id, platform),
  UNIQUE(platform, mapping_value)
);
CREATE TABLE IF NOT EXISTS account_ai_usage_imports (
  guest_account_id TEXT NOT NULL REFERENCES guest_accounts(id) ON DELETE CASCADE,
  account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  usage_period TEXT NOT NULL,
  standard_seconds INTEGER NOT NULL CHECK(standard_seconds >= 0),
  input_tokens INTEGER NOT NULL CHECK(input_tokens >= 0),
  output_tokens INTEGER NOT NULL CHECK(output_tokens >= 0),
  imported_at INTEGER NOT NULL,
  PRIMARY KEY(guest_account_id, usage_period)
);

-- Schema only. There are deliberately no routes or production UI for these.
CREATE TABLE IF NOT EXISTS friend_invites (id TEXT PRIMARY KEY, created_by_account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, child_profile_id TEXT NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE, invite_token_hash TEXT NOT NULL UNIQUE, status TEXT NOT NULL CHECK(status IN ('pending','accepted','expired','revoked')), expires_at INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS friendships (id TEXT PRIMARY KEY, child_profile_a_id TEXT NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE, child_profile_b_id TEXT NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE, approved_by_account_a_id TEXT NOT NULL REFERENCES accounts(id), approved_by_account_b_id TEXT NOT NULL REFERENCES accounts(id), status TEXT NOT NULL CHECK(status IN ('active','blocked','ended')), created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, CHECK(child_profile_a_id <> child_profile_b_id));
CREATE UNIQUE INDEX IF NOT EXISTS friendships_pair ON friendships(child_profile_a_id, child_profile_b_id);
CREATE TABLE IF NOT EXISTS house_visits (id TEXT PRIMARY KEY, friendship_id TEXT NOT NULL REFERENCES friendships(id), host_child_profile_id TEXT NOT NULL REFERENCES child_profiles(id), guest_child_profile_id TEXT NOT NULL REFERENCES child_profiles(id), status TEXT NOT NULL CHECK(status IN ('planned','active','completed','cancelled')), created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS multiplayer_sessions (id TEXT PRIMARY KEY, durable_object_key TEXT NOT NULL UNIQUE, activity TEXT NOT NULL CHECK(activity IN ('house_visit','co_op_minigame','dress_up','cooking','tidy_up','dance','classroom')), status TEXT NOT NULL CHECK(status IN ('forming','active','ended')), created_at INTEGER NOT NULL, ended_at INTEGER);
CREATE TABLE IF NOT EXISTS session_members (session_id TEXT NOT NULL REFERENCES multiplayer_sessions(id) ON DELETE CASCADE, child_profile_id TEXT NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE, parent_account_id TEXT NOT NULL REFERENCES accounts(id), role TEXT NOT NULL CHECK(role IN ('host','guest')), joined_at INTEGER NOT NULL, left_at INTEGER, PRIMARY KEY(session_id, child_profile_id));
