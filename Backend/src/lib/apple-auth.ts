import crypto from 'crypto'
import { SignJWT, createRemoteJWKSet, importPKCS8, jwtVerify } from 'jose'

const issuer = 'https://appleid.apple.com'
const appleKeys = createRemoteJWKSet(new URL(`${issuer}/auth/keys`))

// The app's bundle id: what Apple puts as the identity token's audience for
// native Sign in with Apple on iOS.
function clientId(): string {
  return process.env.APPLE_BUNDLE_ID || 'com.alldocs.app'
}

export interface VerifiedAppleUser {
  sub: string
  email?: string
}

// Checks signature, issuer, audience and expiry against Apple's public keys,
// plus the nonce: the app hashed a random value into the request, so a
// token captured elsewhere can't be replayed here.
export async function verifyAppleIdentityToken(
  identityToken: string,
  rawNonce: string
): Promise<VerifiedAppleUser> {
  const { payload } = await jwtVerify(identityToken, appleKeys, {
    issuer,
    audience: clientId(),
  })
  const expectedNonce = crypto.createHash('sha256').update(rawNonce).digest('hex')
  if (payload.nonce !== expectedNonce) {
    throw new Error('Apple sign-in nonce mismatch')
  }
  if (!payload.sub) throw new Error('Apple token has no subject')

  // email_verified comes as a boolean or as the string "true".
  const verified = payload.email_verified === true || payload.email_verified === 'true'
  const email = typeof payload.email === 'string' && verified ? payload.email : undefined
  return { sub: payload.sub, email }
}

// Exchanging the authorization code and revoking tokens need a "Sign in with
// Apple" key from the Apple Developer account. Without it sign-in still
// works; only the revoke on account deletion is skipped.
export function isAppleRevokeConfigured(): boolean {
  return Boolean(process.env.APPLE_TEAM_ID && process.env.APPLE_KEY_ID && process.env.APPLE_PRIVATE_KEY)
}

async function clientSecret(): Promise<string> {
  const pem = process.env.APPLE_PRIVATE_KEY!.replace(/\\n/g, '\n')
  const key = await importPKCS8(pem, 'ES256')
  return new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: process.env.APPLE_KEY_ID! })
    .setIssuer(process.env.APPLE_TEAM_ID!)
    .setIssuedAt()
    .setExpirationTime('5m')
    .setAudience(issuer)
    .setSubject(clientId())
    .sign(key)
}

async function appleForm(path: string, fields: Record<string, string>) {
  return fetch(`${issuer}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: clientId(),
      client_secret: await clientSecret(),
      ...fields,
    }),
  })
}

// The refresh token is what Apple's revoke endpoint wants later; the
// authorization code is single-use and expires in minutes.
export async function exchangeAppleCode(code: string): Promise<string | null> {
  if (!isAppleRevokeConfigured()) return null
  const res = await appleForm('/auth/token', { code, grant_type: 'authorization_code' })
  if (!res.ok) throw new Error(`Apple token exchange failed (${res.status})`)
  const body = (await res.json()) as { refresh_token?: string }
  return body.refresh_token ?? null
}

// App Store guideline 5.1.1(v): deleting the account must revoke the
// Sign in with Apple tokens.
export async function revokeAppleToken(refreshToken: string): Promise<void> {
  if (!isAppleRevokeConfigured()) return
  const res = await appleForm('/auth/revoke', {
    token: refreshToken,
    token_type_hint: 'refresh_token',
  })
  if (!res.ok) throw new Error(`Apple token revoke failed (${res.status})`)
}
