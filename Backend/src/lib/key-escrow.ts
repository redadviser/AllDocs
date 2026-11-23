import crypto from 'crypto'
import { isLocalDevelopment } from './env'

// Copies of each account's library key (the app's documents are encrypted
// on the phone with it), sealed with this server's KEY_ESCROW_SECRET so a
// database dump alone doesn't reveal them. Bound to the account: a sealed
// value copied to another user's row doesn't open.
//
// Losing KEY_ESCROW_SECRET makes every copy unreadable, so it must also be
// kept outside CapRover (password manager).

export class EscrowNotConfiguredError extends Error {}

function secret(): Buffer {
  const configured = process.env.KEY_ESCROW_SECRET?.trim()
  if (configured) {
    const decoded = Buffer.from(configured, /^[0-9a-f]{64}$/i.test(configured) ? 'hex' : 'base64')
    if (decoded.length !== 32) throw new Error('KEY_ESCROW_SECRET must be 32 bytes (hex or base64)')
    return decoded
  }
  if (!isLocalDevelopment()) {
    throw new EscrowNotConfiguredError('KEY_ESCROW_SECRET is not configured')
  }
  // Development only: derived from the session secret.
  return crypto
    .createHash('sha256')
    .update(`alldocs-key-escrow:${process.env.JWT_SECRET ?? 'dev'}`)
    .digest()
}

export function isEscrowConfigured(): boolean {
  try {
    secret()
    return true
  } catch {
    return false
  }
}

function aad(userId: string): Buffer {
  return Buffer.from(`vault-key:${userId}`)
}

/// `v1.<iv>.<ciphertext>.<tag>` in base64url; the version leaves room to
/// rotate the secret later.
export function seal(userId: string, key: Buffer): string {
  const iv = crypto.randomBytes(12)
  const cipher = crypto.createCipheriv('aes-256-gcm', secret(), iv)
  cipher.setAAD(aad(userId))
  const ciphertext = Buffer.concat([cipher.update(key), cipher.final()])
  return ['v1', ...[iv, ciphertext, cipher.getAuthTag()].map((part) => part.toString('base64url'))].join('.')
}

export function open(userId: string, sealed: string): Buffer {
  const [version, iv, ciphertext, tag] = sealed.split('.')
  if (version !== 'v1' || !iv || !ciphertext || !tag) throw new Error('Unknown sealed key format')
  // A fixed 16-byte tag: Node would otherwise accept a shortened one.
  const decipher = crypto.createDecipheriv('aes-256-gcm', secret(), Buffer.from(iv, 'base64url'), {
    authTagLength: 16,
  })
  decipher.setAAD(aad(userId))
  decipher.setAuthTag(Buffer.from(tag, 'base64url'))
  return Buffer.concat([decipher.update(Buffer.from(ciphertext, 'base64url')), decipher.final()])
}
