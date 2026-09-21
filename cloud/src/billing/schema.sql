-- Family Club billing tables (D1 / SQLite). Agent D owns the migration files;
-- this is the column set cloud/src/billing/repo.ts expects.

CREATE TABLE IF NOT EXISTS purchase_events (
  transaction_id           TEXT PRIMARY KEY,   -- event key: see events.ts eventKey()
  store                    TEXT NOT NULL,      -- apple | google | mock
  original_transaction_id  TEXT NOT NULL,      -- the subscription's identity across renewals
  product_id               TEXT NOT NULL,
  subject_id               TEXT,               -- the clientId that presented it; NULL for store notifications
  payload_hash             TEXT NOT NULL,      -- sha256 of the canonical normalized transaction
  event_time_ms            INTEGER NOT NULL,   -- store ordering key
  source                   TEXT NOT NULL,      -- verify | apple_notification | google_rtdn | mock
  result_json              TEXT NOT NULL,      -- the stored ProcessResult, replayed on duplicates
  processed_at             INTEGER NOT NULL    -- unix seconds
);
CREATE UNIQUE INDEX IF NOT EXISTS purchase_events_transaction_id ON purchase_events (transaction_id);
CREATE INDEX IF NOT EXISTS purchase_events_subscription ON purchase_events (original_transaction_id, event_time_ms);

CREATE TABLE IF NOT EXISTS entitlements (
  subject_id               TEXT PRIMARY KEY,   -- one row per clientId (device / family profile)
  entitlement_id           TEXT NOT NULL,      -- familyClub
  status                   TEXT NOT NULL,      -- active | grace | expired | revoked | none
  period_end               INTEGER NOT NULL,   -- unix seconds
  verified_at              INTEGER NOT NULL,   -- unix seconds the store last confirmed it
  original_transaction_id  TEXT NOT NULL,
  store                    TEXT NOT NULL,
  product_id               TEXT NOT NULL,
  last_event_time_ms       INTEGER NOT NULL,   -- out-of-order guard
  updated_at               INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS entitlements_subscription ON entitlements (original_transaction_id);
