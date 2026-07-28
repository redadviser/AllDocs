import bcrypt from 'bcryptjs'
import crypto from 'crypto'
import { SignJWT, jwtVerify } from 'jose'
import type { Request } from 'express'
import { accountsSql } from './db'

// Own signing secret — deliberately not shared with AllPhotos. A token
// issued here must never be valid on the AllPhotos backend, even though
// both back the same `users` row.
const JWT_SECRET = new TextEncoder().encode(
  process.env.JWT_SECRET || 'default-dev-secret-change-in-production'
)
export const COOKIE_NAME = 'session_token'
const SESSION_DURATION = 60 * 60 * 24 * 30

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

// Reads/writes the `users` table shared with AllPhotos (same Postgres
// server, different database in production). AllDocs never creates or
// touches AllPhotos' own domain tables (profiles, albums, photos, ...).
export async function signUp(email: string, password: string) {
  const existing = await accountsSql`SELECT id FROM users WHERE email = ${email}`
  if (existing.length > 0) throw new Error('Email already registered')

  const id = crypto.randomUUID()
  const passwordHash = await hashPassword(password)

  await accountsSql`INSERT INTO users (id, email, password_hash) VALUES (${id}, ${email}, ${passwordHash})`

  return { user: { id, email }, token: await createToken(id, email) }
}

export async function signIn(email: string, password: string) {
  const rows = await accountsSql`SELECT id, email, password_hash FROM users WHERE email = ${email}`
  if (rows.length === 0) throw new Error('Invalid email or password')

  const user = rows[0]
  const valid = await verifyPassword(password, user.password_hash as string)
  if (!valid) throw new Error('Invalid email or password')

  return {
    user: { id: user.id as string, email: user.email as string },
    token: await createToken(user.id as string, user.email as string),
  }
}

// Used by Google sign-in: the same shared `users` row is reused whenever the
// email matches, so a Google account and a password account with the same
// email resolve to one identity — sign in with either, on either app.
export async function findOrCreateUserByEmail(email: string) {
  const existing = await accountsSql`SELECT id, email FROM users WHERE email = ${email}`
  if (existing.length > 0) {
    const user = { id: existing[0].id as string, email: existing[0].email as string }
    return { user, token: await createToken(user.id, user.email) }
  }

  const id = crypto.randomUUID()
  // Social-only accounts still need a password_hash value (the column is
  // NOT NULL on the users table shared with AllPhotos) — a random, never
  // issued hash satisfies that without creating a guessable password.
  const passwordHash = await hashPassword(crypto.randomUUID())
  await accountsSql`INSERT INTO users (id, email, password_hash) VALUES (${id}, ${email}, ${passwordHash})`

  return { user: { id, email }, token: await createToken(id, email) }
}

export async function getCurrentUserFromToken(
  token: string | undefined
): Promise<{ id: string; email: string } | null> {
  try {
    if (!token) return null

    const { payload } = await jwtVerify(token, JWT_SECRET)
    const userId = payload.sub as string
    const email = payload.email as string
    if (!userId || !email) return null

    const rows = await accountsSql`SELECT id, email FROM users WHERE id = ${userId}`
    if (rows.length === 0) return null

    return { id: rows[0].id as string, email: rows[0].email as string }
  } catch {
    return null
  }
}

export async function getCurrentUser(req: Request): Promise<{ id: string; email: string } | null> {
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
