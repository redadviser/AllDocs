-- =============================================================
-- AllDocs Backend - own database schema (devices this phase; later
-- vaults/documents_metadata/reminders/subscriptions per the roadmap).
-- Applied to the `alldocs` database. The shared `users` table lives in
-- AllPhotos' database instead — see accounts-schema.sql for the local dev
-- stand-in.
-- =============================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

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

COMMIT;
