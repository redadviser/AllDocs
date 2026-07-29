import bcrypt from 'bcryptjs'
import crypto from 'crypto'
import { SignJWT, jwtVerify } from 'jose'
import type { Request } from 'express'
import { accountsSql } from './db'

// Own signing secret — deliberately not shared with AllPhotos. A token
// issued here must never be valid on the AllPhotos backend, even though
// both back the same `users`/`profiles` rows.
const JWT_SECRET = new TextEncoder().encode(
  process.env.JWT_SECRET || 'default-dev-secret-change-in-production'
)
export const COOKIE_NAME = 'session_token'
const SESSION_DURATION = 60 * 60 * 24 * 30

// `plan` is the shared "All" subscription — a purchase in either app is
// meant to unlock premium in both, since it's read from the same profiles
// row AllPhotos already manages billing against.
export interface AccountUser {
  id: string
  email: string
  displayName: string | null
  plan: string
  avatarUrl: string | null
}

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, 10)
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return bcrypt.compare(password, hash)
}

async function createToken(userId: string, email: string): Promise<string> {
  return new SignJWT({ sub: userId, email })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${SESSION_DURATION}s`)
    .sign(JWT_SECRET)
}

function defaultDisplayName(email: string, requested?: string): string {
  const trimmed = requested?.trim()
  return trimmed && trimmed.length > 0 ? trimmed : email.split('@')[0]
}

// Reads/writes the `users` and `profiles` tables shared with AllPhotos (same
// Postgres server, different database in production). AllDocs never touches
// AllPhotos' own domain tables (albums, photos, shelves, ...) or the Google
// Drive-linking columns on profiles (google_access_token, etc.) — only
// display_name and plan.
export async function signUp(email: string, password: string, displayName?: string) {
  const existing = await accountsSql`SELECT id FROM users WHERE email = ${email}`
  if (existing.length > 0) throw new Error('Email already registered')

  const id = crypto.randomUUID()
  const passwordHash = await hashPassword(password)
  const resolvedName = defaultDisplayName(email, displayName)

  await accountsSql`INSERT INTO users (id, email, password_hash) VALUES (${id}, ${email}, ${passwordHash})`
  await accountsSql`INSERT INTO profiles (id, display_name, plan) VALUES (${id}, ${resolvedName}, 'free')`

  const user: AccountUser = { id, email, displayName: resolvedName, plan: 'free', avatarUrl: null }
  return { user, token: await createToken(id, email) }
}

export async function signIn(email: string, password: string) {
  const rows = await accountsSql`
    SELECT u.id, u.email, u.password_hash, p.display_name, p.plan, p.avatar_url
    FROM users u
    LEFT JOIN profiles p ON p.id = u.id
    WHERE u.email = ${email}
  `
  if (rows.length === 0) throw new Error('Invalid email or password')

  const row = rows[0]
  const valid = await verifyPassword(password, row.password_hash as string)
  if (!valid) throw new Error('Invalid email or password')

  const user: AccountUser = {
    id: row.id as string,
    email: row.email as string,
    displayName: (row.display_name as string | null) ?? null,
    plan: (row.plan as string | null) ?? 'free',
    avatarUrl: (row.avatar_url as string | null) ?? null,
  }
  return { user, token: await createToken(user.id, user.email) }
}

// Used by Google sign-in: the same shared `users`/`profiles` rows are reused
// whenever the email matches, so a Google account and a password account
// with the same email resolve to one identity — sign in with either, on
// either app.
export async function findOrCreateUserByEmail(
  email: string,
  displayName?: string,
  pictureUrl?: string
) {
  const existing = await accountsSql`
    SELECT u.id, u.email, p.display_name, p.plan, p.avatar_url
    FROM users u
    LEFT JOIN profiles p ON p.id = u.id
    WHERE u.email = ${email}
  `
  if (existing.length > 0) {
    const row = existing[0]
    // Don't overwrite a photo the user may already have set — only fill it
    // in the first time Google gives us one and profiles.avatar_url is empty.
    if (pictureUrl && !row.avatar_url) {
      await accountsSql`UPDATE profiles SET avatar_url = ${pictureUrl} WHERE id = ${row.id}`
    }
    const user: AccountUser = {
      id: row.id as string,
      email: row.email as string,
      displayName: (row.display_name as string | null) ?? null,
      plan: (row.plan as string | null) ?? 'free',
      avatarUrl: (pictureUrl && !row.avatar_url ? pictureUrl : row.avatar_url as string | null) ?? null,
    }
    return { user, token: await createToken(user.id, user.email) }
  }

  const id = crypto.randomUUID()
  // Social-only accounts still need a password_hash value (the column is
  // NOT NULL on the users table shared with AllPhotos) — a random, never
  // issued hash satisfies that without creating a guessable password.
  const passwordHash = await hashPassword(crypto.randomUUID())
  const resolvedName = defaultDisplayName(email, displayName)

  await accountsSql`INSERT INTO users (id, email, password_hash) VALUES (${id}, ${email}, ${passwordHash})`
  await accountsSql`
    INSERT INTO profiles (id, display_name, plan, avatar_url)
    VALUES (${id}, ${resolvedName}, 'free', ${pictureUrl ?? null})
  `

  const user: AccountUser = {
    id,
    email,
    displayName: resolvedName,
    plan: 'free',
    avatarUrl: pictureUrl ?? null,
  }
  return { user, token: await createToken(id, email) }
}

export async function getCurrentUserFromToken(
  token: string | undefined
): Promise<AccountUser | null> {
  try {
    if (!token) return null

    const { payload } = await jwtVerify(token, JWT_SECRET)
    const userId = payload.sub as string
    const email = payload.email as string
    if (!userId || !email) return null

    const rows = await accountsSql`
      SELECT u.id, u.email, p.display_name, p.plan, p.avatar_url
      FROM users u
      LEFT JOIN profiles p ON p.id = u.id
      WHERE u.id = ${userId}
    `
    if (rows.length === 0) return null

    const row = rows[0]
    return {
      id: row.id as string,
      email: row.email as string,
      displayName: (row.display_name as string | null) ?? null,
      plan: (row.plan as string | null) ?? 'free',
      avatarUrl: (row.avatar_url as string | null) ?? null,
    }
  } catch {
    return null
  }
}

export async function getCurrentUser(req: Request): Promise<AccountUser | null> {
  const token = req.cookies?.[COOKIE_NAME]
  return getCurrentUserFromToken(token)
}

export function sessionCookieConfig(token: string) {
  return {
    name: COOKIE_NAME,
    value: token,
    options: {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax' as const,
      maxAge: SESSION_DURATION * 1000,
      path: '/',
    },
  }
}

export function clearSessionCookieConfig() {
  return {
    name: COOKIE_NAME,
    options: {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      sameSite: 'lax' as const,
      maxAge: 0,
      path: '/',
    },
  }
}
