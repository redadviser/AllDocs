import { OAuth2Client } from 'google-auth-library'

const client = new OAuth2Client()

// Mobile "Sign in with Google" registers a separate OAuth client per
// platform (iOS/Android/Web) under the same Google Cloud project; the ID
// token's audience can be any of them, so all configured ones are accepted.
function configuredAudiences(): string[] {
  return [
    process.env.GOOGLE_SIGNIN_IOS_CLIENT_ID,
    process.env.GOOGLE_SIGNIN_ANDROID_CLIENT_ID,
    process.env.GOOGLE_SIGNIN_WEB_CLIENT_ID,
  ].filter((value): value is string => Boolean(value))
}

export function isGoogleSignInConfigured(): boolean {
  return configuredAudiences().length > 0
}

export interface VerifiedGoogleUser {
  email: string
  name?: string
  picture?: string
}

// Verifies the ID token's signature/issuer/audience/expiry against Google's
// public keys and returns the verified email (+ display name, if Google
// shared one). Never trust a client-supplied email directly — only what
// Google itself signed.
export async function verifyGoogleIdToken(idToken: string): Promise<VerifiedGoogleUser> {
  const audiences = configuredAudiences()
  if (audiences.length === 0) {
    throw new Error('Google sign-in is not configured on this server')
  }

  const ticket = await client.verifyIdToken({ idToken, audience: audiences })
  const payload = ticket.getPayload()

  if (!payload?.email || payload.email_verified !== true) {
    throw new Error('Google account has no verified email')
  }

  return { email: payload.email, name: payload.name, picture: payload.picture }
}
