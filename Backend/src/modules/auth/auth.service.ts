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
async function registerDevice(userId: string, device?: DeviceInfo) {
  if (!device?.id) return

  await sql`
    INSERT INTO devices (id, user_id, platform, last_seen_at)
    VALUES (${device.id}, ${userId}, ${device.platform ?? 'unknown'}, NOW())
    ON CONFLICT (id) DO UPDATE
      SET user_id = EXCLUDED.user_id,
          platform = EXCLUDED.platform,
          last_seen_at = NOW()
  `
}

export async function login(email: string, password: string, device?: DeviceInfo) {
  const result = await signIn(email, password)
  await registerDevice(result.user.id, device)
  return result
}

export async function signup(email: string, password: string, device?: DeviceInfo) {
  const result = await signUp(email, password)
  await registerDevice(result.user.id, device)
  return result
}

export async function loginWithGoogle(idToken: string, device?: DeviceInfo) {
  const { email } = await verifyGoogleIdToken(idToken)
  const result = await findOrCreateUserByEmail(email)
  await registerDevice(result.user.id, device)
  return result
}
