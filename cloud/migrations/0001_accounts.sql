-- Little Days cloud: parent accounts, child profiles, devices, consent.
-- Data minimisation is the rule (docs/ALIZ_TUTOR_PRIVACY_REVIEW.md): no real
-- names, no e-mail in clear, no device serials, no audio, no transcripts.
--
-- Retention: parent_accounts / child_profiles / consent_status live until the
-- parent deletes the account (DELETE /v1/parents/me, follow-up). Devices are
-- purged when their parent is deleted; a device row carries no identifier
-- beyond the pseudonymous per-install clientId the app invents.

CREATE TABLE IF NOT EXISTS parent_accounts (
  id               TEXT PRIMARY KEY,                 -- uuid
  provider         TEXT NOT NULL,                    -- 'dev' | 'apple' | 'google'
  subject_hash     TEXT NOT NULL,                    -- HMAC(secret, provider subject); never the raw subject
  email_hash       TEXT,                             -- HMAC(secret, lowercased e-mail) when the provider gives one; optional
  consent_version  INTEGER NOT NULL DEFAULT 0,       -- highest privacy-policy version the parent accepted
  created_at       INTEGER NOT NULL,                 -- unix ms
  updated_at       INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS parent_accounts_subject
  ON parent_accounts (provider, subject_hash);

CREATE TABLE IF NOT EXISTS child_profiles (
  id                 TEXT PRIMARY KEY,               -- uuid
  parent_id          TEXT NOT NULL REFERENCES parent_accounts(id) ON DELETE CASCADE,
  nickname           TEXT NOT NULL,                  -- a display nickname or avatar label, NEVER a real name (client-side rule + 24 char cap)
  avatar_id          TEXT,                           -- one of the bundled avatar ids
  birth_year_bucket  TEXT,                           -- optional coarse bucket such as '2020-2021'; never a birth date
  locale             TEXT NOT NULL DEFAULT 'en-US',
  created_at         INTEGER NOT NULL,
  updated_at         INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS child_profiles_parent ON child_profiles (parent_id);

CREATE TABLE IF NOT EXISTS devices (
  id           TEXT PRIMARY KEY,                     -- the app's pseudonymous per-install clientId (regex-limited)
  parent_id    TEXT NOT NULL REFERENCES parent_accounts(id) ON DELETE CASCADE,
  platform     TEXT NOT NULL DEFAULT 'unknown',      -- 'ios' | 'android' | 'macos' | 'unknown'
  app_version  TEXT,                                 -- semver string; no OS build, no model, no push token
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS devices_parent ON devices (parent_id);

CREATE TABLE IF NOT EXISTS consent_status (
  parent_id   TEXT NOT NULL REFERENCES parent_accounts(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL,                         -- 'privacy' | 'ai_tutor' | 'voice'
  version     INTEGER NOT NULL,                      -- version of the text that was shown
  granted_at  INTEGER,                               -- unix ms; NULL = never granted
  revoked_at  INTEGER,                               -- unix ms; NULL = still in force
  updated_at  INTEGER NOT NULL,
  PRIMARY KEY (parent_id, kind)
);
