import crypto from 'crypto'
import { sql } from '../../lib/db'
import { open, seal } from '../../lib/key-escrow'

export class VaultKeyError extends Error {
  constructor(
    public status: number,
    message: string,
    public code?: string
  ) {
    super(message)
  }
}

const KEY_CHECK = /^[0-9a-f]{64}$/

/// The account's library key (base64) and its check value, or null.
export async function getKey(userId: string): Promise<{ key: string; keyCheck: string } | null> {
  const rows = await sql`SELECT sealed, key_check FROM vault_keys WHERE user_id = ${userId}`
  if (rows.length === 0) return null
  return {
    key: open(userId, rows[0].sealed as string).toString('base64'),
    keyCheck: rows[0].key_check as string,
  }
}

/// Stores the account's library key once. Never replaces a stored one: an
/// app with a bug (or a second phone with its own key) can't destroy the
/// copy that opens the existing library.
export async function putKey(
  userId: string,
  input: { key?: unknown; keyCheck?: unknown }
): Promise<'created' | 'same'> {
  const key = typeof input.key === 'string' ? Buffer.from(input.key, 'base64') : null
  // Buffer.from skips bad characters, so check it round-trips exactly.
  if (!key || key.length !== 32 || key.toString('base64') !== input.key) {
    throw new VaultKeyError(400, 'key must be 32 bytes in base64', 'badKey')
  }
  const keyCheck = typeof input.keyCheck === 'string' ? input.keyCheck.toLowerCase() : ''
  if (!KEY_CHECK.test(keyCheck)) {
    throw new VaultKeyError(400, 'keyCheck must be 64 hex characters', 'badKey')
  }

  const inserted = await sql`
    INSERT INTO vault_keys (user_id, sealed, key_check)
    VALUES (${userId}, ${seal(userId, key)}, ${keyCheck})
    ON CONFLICT (user_id) DO NOTHING
    RETURNING user_id
  `
  if (inserted.length > 0) return 'created'

  const stored = await getKey(userId)
  if (
    stored &&
    stored.keyCheck === keyCheck &&
    crypto.timingSafeEqual(Buffer.from(stored.key, 'base64'), key)
  ) {
    return 'same'
  }
  throw new VaultKeyError(409, 'A different key is already stored', 'conflict')
}
