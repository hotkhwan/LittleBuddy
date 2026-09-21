-- Account privacy controls (parent portal): deletion tombstones and the
-- entitlement audit mark. Additive only.
--
-- Deletion (DELETE /v1/parents/me) removes children, devices, consent,
-- progress, sessions, quota mirrors and idempotency rows, sets
-- purchase_events.parent_id to NULL, marks entitlements revoked (kept for
-- refund / tax audit, never deleted) and turns the parent row into a
-- TOMBSTONE: email_hash cleared, consent_version 0, deleted_at set,
-- tombstone_until = deleted_at + 30 days. The (provider, subject_hash) pair
-- stays on the tombstone so the same store identity cannot silently
-- re-create the account inside the window (POST /v1/parents answers 409
-- with `availableAt`). Once the window passes, the next sign-in of anyone
-- (expireTombstones) deletes tombstones that hold no entitlement rows and
-- anonymises the rest (subject_hash = 'deleted:' || id), so a returning
-- parent gets a brand-new account with no old data.

ALTER TABLE parent_accounts ADD COLUMN deleted_at INTEGER;        -- unix ms; NULL = live account
ALTER TABLE parent_accounts ADD COLUMN tombstone_until INTEGER;   -- unix ms; NULL = live or already anonymised
CREATE INDEX IF NOT EXISTS parent_accounts_tombstone ON parent_accounts (tombstone_until);

ALTER TABLE entitlements ADD COLUMN revoked_reason TEXT;          -- 'account_deleted' when revoked by DELETE /v1/parents/me; NULL otherwise
