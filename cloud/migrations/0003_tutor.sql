-- Aliz AI Tutor: sessions, the per-child daily counter, usage accounting and
-- request idempotency. NOTHING here stores what a child said or how they
-- sounded: no transcript column, no audio column, numbers and ids only.
--
-- Retention (enforced by the scheduled purge in cloud/src/db/retention.ts):
--   tutor_sessions  : RETENTION_DAYS (default 30) after ended_at / started_at
--   daily_quota     : RETENTION_DAYS after day_utc
--   usage_events    : RETENTION_DAYS after created_at (monthly budget only needs the current month)
--   api_idempotency : 24 h after created_at

CREATE TABLE IF NOT EXISTS tutor_sessions (
  id             TEXT PRIMARY KEY,                   -- uuid; also the Durable Object name
  child_id       TEXT NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
  device_id      TEXT,                               -- devices.id (clientId); nullable so a purged device keeps history counts
  lesson_id      TEXT NOT NULL,
  mode           TEXT NOT NULL DEFAULT 'turns',      -- 'turns' | 'realtime'
  provider       TEXT NOT NULL DEFAULT 'mock',
  started_at     INTEGER NOT NULL,                   -- unix ms (server clock)
  ended_at       INTEGER,                            -- unix ms; NULL while live
  reason         TEXT,                               -- 'client_end' | 'quota_exhausted' | 'daily_turns' | 'idle' | 'parent_stop' | 'token_expired' | ...
  seconds_used   REAL NOT NULL DEFAULT 0,            -- seconds charged to the daily counter by this session
  turn_count     INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS tutor_sessions_child   ON tutor_sessions (child_id, started_at);
CREATE INDEX IF NOT EXISTS tutor_sessions_started ON tutor_sessions (started_at);

-- Reporting mirror of the QuotaDO counter (the Durable Object is the
-- authority; this table is what dashboards, retention and "delete my data" see).
CREATE TABLE IF NOT EXISTS daily_quota (
  child_id           TEXT NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
  day_utc            TEXT NOT NULL,                  -- 'YYYY-MM-DD'
  seconds_used       REAL NOT NULL DEFAULT 0,
  turns_used         INTEGER NOT NULL DEFAULT 0,
  allowance_seconds  INTEGER NOT NULL,               -- allowance in force at the last charge (free 300 / family_club 1800)
  updated_at         INTEGER NOT NULL,
  PRIMARY KEY (child_id, day_utc)
);
CREATE INDEX IF NOT EXISTS daily_quota_day ON daily_quota (day_utc);

-- Numbers only. `kind` names the accounting row type; no text columns beyond ids.
CREATE TABLE IF NOT EXISTS usage_events (
  id             TEXT PRIMARY KEY,                   -- uuid
  session_id     TEXT NOT NULL,                      -- tutor_sessions.id (no FK so a purged session leaves its month total intact until its own purge)
  kind           TEXT NOT NULL,                      -- 'turn' | 'realtime_mint' | 'realtime_usage'
  tokens_in      INTEGER NOT NULL DEFAULT 0,
  tokens_out     INTEGER NOT NULL DEFAULT 0,
  audio_seconds  REAL NOT NULL DEFAULT 0,
  cost_usd_micro INTEGER NOT NULL DEFAULT 0,         -- estimated cost in millionths of a USD
  created_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS usage_events_session ON usage_events (session_id);
CREATE INDEX IF NOT EXISTS usage_events_created ON usage_events (created_at);

-- Idempotent turns: `key` = HMAC(secret, sessionId + Idempotency-Key). The
-- request hash is a salted HMAC of the body so the transcript is never
-- recoverable from this row; the stored response is the validated TutorTurn
-- reply (already child-safe, contains no transcript).
CREATE TABLE IF NOT EXISTS api_idempotency (
  key            TEXT PRIMARY KEY,
  session_id     TEXT NOT NULL,
  request_hash   TEXT NOT NULL,
  response_hash  TEXT NOT NULL,
  status         INTEGER NOT NULL,
  response_json  TEXT NOT NULL,
  created_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS api_idempotency_created ON api_idempotency (created_at);
CREATE INDEX IF NOT EXISTS api_idempotency_session ON api_idempotency (session_id);
