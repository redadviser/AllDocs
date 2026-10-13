-- =============================================================
-- AllDocs Backend - database schema: accounts, devices, subscriptions
-- (later vaults/documents_metadata/reminders per the roadmap).
-- Idempotent: applied by the server on every start (src/lib/schema.ts) and
-- by the local docker-compose on first boot.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_lower ON users ((LOWER(email)));

CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  display_name TEXT,
  plan TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'premium', 'pro')),
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- "Forgot password": one row per emailed link. Only a SHA-256 of the token
-- is stored, so a leaked table can't be used to reset anyone's password.
CREATE TABLE IF NOT EXISTS password_resets (
  token_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_password_resets_user ON password_resets (user_id);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  platform TEXT NOT NULL DEFAULT 'unknown',
  name TEXT,
  push_token TEXT,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devices_user ON devices (user_id);

-- One session per phone *and account*: a phone signed in to two accounts
-- has a row for each. (The key used to be the phone alone, so signing in
-- with a second account took the row over and broke the first account's
-- session there.)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'devices_pkey'
      AND conrelid = 'devices'::regclass
      AND array_length(conkey, 1) = 1
  ) THEN
    ALTER TABLE devices DROP CONSTRAINT devices_pkey;
    ALTER TABLE devices ADD CONSTRAINT devices_pkey PRIMARY KEY (id, user_id);
  END IF;
END $$;

-- Subscriptions (bought in the app through Adapty). profiles.plan is the
-- paid plan; plan_expires_at is when the current period ends (NULL = no
-- end known: free, lifetime or renewing in a grace period). An expired
-- plan reads as 'free' (see effectivePlanColumn in src/lib/plans.ts).
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_billing_period TEXT NOT NULL DEFAULT 'monthly';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_expires_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_updated_at TIMESTAMPTZ;
-- 'debug' while a tester picked the plan by hand (POST /api/plans/debug):
-- syncing from the store then leaves it alone until they go back.
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_source TEXT NOT NULL DEFAULT 'store';

-- Every Adapty webhook received, as sent, for support and debugging.
CREATE TABLE IF NOT EXISTS subscription_events (
  id BIGSERIAL PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE SET NULL,
  customer_user_id TEXT,
  event_type TEXT NOT NULL,
  environment TEXT,
  payload JSONB NOT NULL,
  received_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscription_events_user ON subscription_events (user_id, received_at DESC);

-- Document requests (Vault): a link someone else uses to send files. Only
-- a hash of the link's token is kept. Files wait encrypted on disk
-- (stored_name) until the requester's app collects them, then are deleted.
CREATE TABLE IF NOT EXISTS document_requests (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  message TEXT,
  language TEXT NOT NULL DEFAULT 'pt',
  album_id TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_document_requests_user ON document_requests (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS document_request_files (
  id TEXT PRIMARY KEY,
  request_id TEXT NOT NULL REFERENCES document_requests(id) ON DELETE CASCADE,
  original_name TEXT NOT NULL,
  content_type TEXT,
  size_bytes BIGINT NOT NULL,
  stored_name TEXT,
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  received_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_document_request_files_request ON document_request_files (request_id);

-- Document assistant (Vault): requests per account per month (YYYY-MM),
-- for the fair-use allowance. No question or document text is stored.
CREATE TABLE IF NOT EXISTS assistant_usage (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  month TEXT NOT NULL,
  requests INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, month)
);

-- Secure shares (Vault): one of the user's documents behind a link that
-- expires, can need a code and can be revoked. The file waits encrypted
-- (stored_name, see src/lib/file-vault.ts) and is deleted once the link
-- stops working. Only hashes of the link token and of the code are kept.
CREATE TABLE IF NOT EXISTS document_shares (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  file_name TEXT NOT NULL,
  content_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  stored_name TEXT,
  language TEXT NOT NULL DEFAULT 'pt',
  code_hash TEXT,
  failed_attempts INTEGER NOT NULL DEFAULT 0,
  max_views INTEGER,
  view_count INTEGER NOT NULL DEFAULT 0,
  last_viewed_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_document_shares_user ON document_shares (user_id, created_at DESC);

-- Device sync (Vault). Everything a device sends is encrypted on the phone
-- with a key only the user's devices have (it travels between them in a QR
-- code); the server stores opaque bytes and relays them until every device
-- has them.
CREATE TABLE IF NOT EXISTS sync_circles (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  -- HMAC of a fixed text under the key: lets a joining device check it has
  -- the right key without the server ever seeing it.
  key_check TEXT NOT NULL,
  -- Changes up to here were deleted (every device had them, or they were
  -- too old): a device behind this needs a snapshot instead.
  purged_upto BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS sync_devices (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  platform TEXT,
  -- Last change this device has applied (it asks for what comes after).
  cursor BIGINT NOT NULL DEFAULT 0,
  -- Joined (or fell too far behind) and waits for another device to send
  -- it the whole library's state.
  needs_snapshot BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_devices_user ON sync_devices (user_id);
-- The phone's session (devices.id): ending that session — signing out,
-- or from another phone — takes it out of sync too.
ALTER TABLE sync_devices ADD COLUMN IF NOT EXISTS session_device_id TEXT;

CREATE TABLE IF NOT EXISTS sync_pairings (
  code_hash TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_by TEXT NOT NULL,
  device_id TEXT,
  expires_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_changes (
  seq BIGSERIAL PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  payload BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sync_changes_user ON sync_changes (user_id, seq);

-- Document files on their way between devices (encrypted on the phone).
CREATE TABLE IF NOT EXISTS sync_blobs (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blob_id TEXT NOT NULL,
  stored_name TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, blob_id)
);

-- Which devices still have to download a blob; it's deleted when none do.
CREATE TABLE IF NOT EXISTS sync_blob_needs (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blob_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  PRIMARY KEY (user_id, blob_id, device_id)
);

-- Files a device is missing and asked the others to send.
CREATE TABLE IF NOT EXISTS sync_blob_requests (
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blob_id TEXT NOT NULL,
  device_id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, blob_id, device_id)
);

-- The whole library's state, sent by one device for another that needs it.
CREATE TABLE IF NOT EXISTS sync_snapshots (
  device_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  upto_seq BIGINT NOT NULL,
  stored_name TEXT NOT NULL,
  size_bytes BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Resetting the hidden albums' PIN (it lives on the phone): a code sent to
-- the account's email, then a wait (24 h) before the app may set a new one,
-- with a warning email that can cancel it. Only hashes of the code and of
-- the cancel link's token are kept.
CREATE TABLE IF NOT EXISTS hidden_pin_resets (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  code_expires_at TIMESTAMPTZ NOT NULL,
  verified_at TIMESTAMPTZ,
  ready_at TIMESTAMPTZ,
  cancel_token_hash TEXT UNIQUE,
  cancelled_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_hidden_pin_resets_user ON hidden_pin_resets (user_id, created_at DESC);

COMMIT;
