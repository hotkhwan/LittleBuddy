-- Entitlements are decided by the server from store events (Agent F,
-- cloud/src/billing/**) or a dev grant. A client never declares one.
--
-- Retention: entitlements are the purchase record and are kept for the life of
-- the account (tax / refund disputes). purchase_events keep the store's
-- transaction id and a hash of the payload only, never the raw receipt.

CREATE TABLE IF NOT EXISTS entitlements (
  parent_id        TEXT NOT NULL REFERENCES parent_accounts(id) ON DELETE CASCADE,
  product_id       TEXT NOT NULL,                    -- e.g. little_days.family_club.monthly
  source           TEXT NOT NULL,                    -- 'apple' | 'google' | 'dev'
  status           TEXT NOT NULL,                    -- 'active' | 'expired' | 'revoked' | 'grace'
  period_end       INTEGER,                          -- unix ms; NULL = open-ended (dev only)
  raw_receipt_ref  TEXT,                             -- opaque store reference (originalTransactionId / purchaseToken hash); nullable
  updated_at       INTEGER NOT NULL,
  PRIMARY KEY (parent_id, product_id, source)
);
CREATE INDEX IF NOT EXISTS entitlements_active
  ON entitlements (parent_id, status, period_end);

-- Store notifications and verify calls are idempotent on transaction_id:
-- a replayed App Store / Play notification is a no-op (UNIQUE below).
CREATE TABLE IF NOT EXISTS purchase_events (
  id              TEXT PRIMARY KEY,                  -- uuid
  store           TEXT NOT NULL,                     -- 'apple' | 'google' | 'dev'
  transaction_id  TEXT NOT NULL UNIQUE,              -- store transaction / notification id
  product_id      TEXT NOT NULL,
  parent_id       TEXT REFERENCES parent_accounts(id) ON DELETE SET NULL,
  status          TEXT NOT NULL,                     -- 'received' | 'applied' | 'ignored' | 'invalid'
  payload_hash    TEXT NOT NULL,                     -- sha256 of the signed payload; the payload itself is not stored
  processed_at    INTEGER NOT NULL                   -- unix ms
);
CREATE INDEX IF NOT EXISTS purchase_events_parent ON purchase_events (parent_id, processed_at);
