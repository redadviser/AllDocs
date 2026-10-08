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

-- Subscriptions (bought in the app through Adapty). profiles.plan is the
-- paid plan; plan_expires_at is when the current period ends (NULL = no
-- end known: free, lifetime or renewing in a grace period). An expired
-- plan reads as 'free' (see effectivePlanColumn in src/lib/plans.ts).
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_billing_period TEXT NOT NULL DEFAULT 'monthly';
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_expires_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS plan_updated_at TIMESTAMPTZ;

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

COMMIT;
