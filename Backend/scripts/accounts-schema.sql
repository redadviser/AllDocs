-- =============================================================
-- Local dev stand-in for the shared accounts database. In production
-- ACCOUNTS_POSTGRES_* points at the real AllPhotos database instead, which
-- already has `users`/`profiles` tables shaped exactly like this (AllDocs
-- only ever reads/writes display_name and plan on profiles — never the
-- Google Drive-linking columns AllPhotos also keeps there).
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

COMMIT;
