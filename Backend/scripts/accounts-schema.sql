-- =============================================================
-- Local dev stand-in for the shared accounts database. In production
-- ACCOUNTS_POSTGRES_* points at the real AllPhotos database instead, which
-- already has a `users` table shaped exactly like this.
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

COMMIT;
