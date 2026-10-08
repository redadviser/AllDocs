import crypto from 'crypto'
import { mkdir, readFile, rm, writeFile } from 'fs/promises'
import path from 'path'

// Files people send through document requests wait here — encrypted
// (AES-256-GCM), one file each — only until the requester's app collects
// them. UPLOADS_DIR must be a persistent volume in production.

const DIR = process.env.UPLOADS_DIR?.trim() || path.resolve(process.cwd(), 'data/uploads')

function key(): Buffer {
  const configured = process.env.UPLOADS_ENCRYPTION_KEY?.trim()
  if (configured) {
    const decoded = Buffer.from(configured, /^[0-9a-f]{64}$/i.test(configured) ? 'hex' : 'base64')
    if (decoded.length !== 32) throw new Error('UPLOADS_ENCRYPTION_KEY must be 32 bytes (hex or base64)')
    return decoded
  }
  if (process.env.NODE_ENV === 'production') {
    throw new Error('UPLOADS_ENCRYPTION_KEY is not configured')
  }
  // Development only: a key derived from the session secret.
  return crypto
    .createHash('sha256')
    .update(`alldocs-uploads:${process.env.JWT_SECRET ?? 'dev'}`)
    .digest()
}

function pathFor(name: string): string {
  if (!/^[0-9a-f-]{36}$/.test(name)) throw new Error('Invalid stored file name')
  return path.join(DIR, name)
}

/// Stores [bytes] encrypted; returns the name to read or delete it by.
export async function storeEncrypted(bytes: Buffer): Promise<string> {
  await mkdir(DIR, { recursive: true })
  const name = crypto.randomUUID()
  const iv = crypto.randomBytes(12)
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv)
  const encrypted = Buffer.concat([cipher.update(bytes), cipher.final()])
  // Layout: 12-byte IV, 16-byte auth tag, ciphertext.
  await writeFile(pathFor(name), Buffer.concat([iv, cipher.getAuthTag(), encrypted]))
  return name
}

export async function readDecrypted(name: string): Promise<Buffer> {
  const data = await readFile(pathFor(name))
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(), data.subarray(0, 12))
  decipher.setAuthTag(data.subarray(12, 28))
  return Buffer.concat([decipher.update(data.subarray(28)), decipher.final()])
}

export async function removeStored(name: string): Promise<void> {
  await rm(pathFor(name), { force: true })
}
