import { findOrCreateUserByEmail, signIn, signUp } from '../../lib/auth'
import { exchangeAppleCode, verifyAppleIdentityToken } from '../../lib/apple-auth'
import { sql } from '../../lib/db'
import { verifyGoogleIdToken } from '../../lib/google-auth'

export interface DeviceInfo {
  id?: string
  platform?: string
  name?: string
}

// AllDocs-specific: tracks which devices are signed into an account so the
// "sessions and devices" security surface has real data, and so later
// phases (push reminders) have somewhere to store a push token per device.
//
// Best-effort by design: this must never fail login/signup/Google sign-in.
// The account (users/profiles) is the source of
// truth; device tracking is secondary bookkeeping. A schema drift or a
// transient issue here (e.g. this table missing a migration on a fresh
// deploy) should degrade to "no device recorded", not "couldn't sign in" —
// which is exactly what happened before this was wrapped: the devices
// INSERT threw when the table didn't exist yet, and that failure aborted
// the whole request even though the users/profiles rows had already
// committed.
async function registerDevice(userId: string, device?: DeviceInfo) {
  if (!device?.id) return

  try {
    await sql`
      INSERT INTO devices (id, user_id, platform, name, last_seen_at)
      VALUES (${device.id}, ${userId}, ${device.platform ?? 'unknown'}, ${device.name ?? null}, NOW())
      ON CONFLICT (id, user_id) DO UPDATE
        SET platform = EXCLUDED.platform,
            name = EXCLUDED.name,
            last_seen_at = NOW()
    `
  } catch (error) {
    console.error('registerDevice failed (non-fatal):', error)
  }
}

export async function login(email: string, password: string, device?: DeviceInfo) {
  const result = await signIn(email, password, device?.id)
  await registerDevice(result.user.id, device)
  return result
}

export async function signup(
  email: string,
  password: string,
  displayName?: string,
  device?: DeviceInfo
) {
  const result = await signUp(email, password, displayName, device?.id)
  await registerDevice(result.user.id, device)
  return result
}

export async function loginWithGoogle(idToken: string, device?: DeviceInfo) {
  const { email, name, picture } = await verifyGoogleIdToken(idToken)
  const result = await findOrCreateUserByEmail(email, name, picture, device?.id)
  await registerDevice(result.user.id, device)
  return result
}

// Apple identifies the person by `sub`, stable for this app. The email can
// be a private relay address, and Apple may only send it the first time,
// so the account is found by `sub` first and by email only to link it.
export async function loginWithApple(
  identityToken: string,
  rawNonce: string,
  authorizationCode?: string,
  displayName?: string,
  device?: DeviceInfo
) {
  const { sub, email } = await verifyAppleIdentityToken(identityToken, rawNonce)

  const linked = await sql`SELECT email FROM users WHERE apple_sub = ${sub}`
  const accountEmail = (linked[0]?.email as string | undefined) ?? email
  if (!accountEmail) throw new Error('Apple did not share an email address')

  const result = await findOrCreateUserByEmail(accountEmail, displayName, undefined, device?.id)
  if (linked.length === 0) {
    await sql`UPDATE users SET apple_sub = ${sub} WHERE id = ${result.user.id} AND apple_sub IS NULL`
  }
  if (authorizationCode) {
    // Only needed to revoke on account deletion; never blocks sign-in.
    try {
      const refreshToken = await exchangeAppleCode(authorizationCode)
      if (refreshToken) {
        await sql`UPDATE users SET apple_refresh_token = ${refreshToken} WHERE id = ${result.user.id}`
      }
    } catch (error) {
      console.error('Apple code exchange failed (non-fatal):', error)
    }
  }
  await registerDevice(result.user.id, device)
  return result
}
