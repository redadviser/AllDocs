import { findOrCreateUserByEmail, signIn, signUp } from '../../lib/auth'
import { sql } from '../../lib/db'
import { verifyGoogleIdToken } from '../../lib/google-auth'

export interface DeviceInfo {
  id?: string
  platform?: string
}

// AllDocs-specific: tracks which devices are signed into an account so the
// "sessions and devices" security surface has real data, and so later
// phases (push reminders) have somewhere to store a push token per device.
// Lives in AllDocs' own database, never AllPhotos'.
//
// Best-effort by design: this must never fail login/signup/Google sign-in.
// The account (users/profiles, shared with AllPhotos) is the source of
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
      INSERT INTO devices (id, user_id, platform, last_seen_at)
      VALUES (${device.id}, ${userId}, ${device.platform ?? 'unknown'}, NOW())
      ON CONFLICT (id) DO UPDATE
        SET user_id = EXCLUDED.user_id,
            platform = EXCLUDED.platform,
            last_seen_at = NOW()
    `
  } catch (error) {
    console.error('registerDevice failed (non-fatal):', error)
  }
}

export async function login(email: string, password: string, device?: DeviceInfo) {
  const result = await signIn(email, password)
  await registerDevice(result.user.id, device)
  return result
}

export async function signup(
  email: string,
  password: string,
  displayName?: string,
  device?: DeviceInfo
) {
  const result = await signUp(email, password, displayName)
  await registerDevice(result.user.id, device)
  return result
}

export async function loginWithGoogle(idToken: string, device?: DeviceInfo) {
  const { email, name, picture } = await verifyGoogleIdToken(idToken)
  const result = await findOrCreateUserByEmail(email, name, picture)
  await registerDevice(result.user.id, device)
  return result
}
