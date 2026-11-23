import crypto from 'crypto'
import { createReadStream, createWriteStream } from 'fs'
import { appendFile, mkdir, open, readFile, rename, rm, stat, writeFile } from 'fs/promises'
import path from 'path'
import { Readable, Transform } from 'stream'
import { pipeline } from 'stream/promises'

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

// Files written by storeEncryptedStream carry this suffix: their layout is
// IV, ciphertext, auth tag (the tag is only known at the end of a stream).
const STREAMED = '.gcm2'

export class StoredTooLargeError extends Error {}

function pathFor(name: string): string {
  if (!/^[0-9a-f-]{36}(\.gcm2)?$/.test(name)) throw new Error('Invalid stored file name')
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

/// Streams [source] to disk encrypted, failing once it passes [maxBytes],
/// so a large file never sits in memory. Returns the name to read or
/// delete it by and the plaintext size (0 = nothing was sent).
export async function storeEncryptedStream(
  source: Readable,
  maxBytes: number
): Promise<{ name: string; size: number }> {
  await mkdir(DIR, { recursive: true })
  const name = `${crypto.randomUUID()}${STREAMED}`
  const target = pathFor(name)
  const temp = `${target}.part`
  const iv = crypto.randomBytes(12)
  const cipher = crypto.createCipheriv('aes-256-gcm', key(), iv)
  let size = 0
  const limit = new Transform({
    transform(chunk: Buffer, _encoding, callback) {
      size += chunk.length
      if (size > maxBytes) callback(new StoredTooLargeError('File too large'))
      else callback(null, chunk)
    },
  })
  try {
    await writeFile(temp, iv)
    await pipeline(source, limit, cipher, createWriteStream(temp, { flags: 'a' }))
    await appendFile(temp, cipher.getAuthTag())
    await rename(temp, target)
  } catch (error) {
    await rm(temp, { force: true })
    throw error
  }
  return { name, size }
}

/// A stored file as a decrypting stream, plus its plaintext size. Files
/// from storeEncrypted are small and decrypted in memory.
export async function openDecrypted(name: string): Promise<{ stream: Readable; size: number }> {
  if (!name.endsWith(STREAMED)) {
    const bytes = await readDecrypted(name)
    return { stream: Readable.from([bytes]), size: bytes.length }
  }
  const file = pathFor(name)
  const { size } = await stat(file)
  const iv = Buffer.alloc(12)
  const tag = Buffer.alloc(16)
  const handle = await open(file, 'r')
  try {
    await handle.read(iv, 0, 12, 0)
    await handle.read(tag, 0, 16, size - 16)
  } finally {
    await handle.close()
  }
  const decipher = crypto.createDecipheriv('aes-256-gcm', key(), iv)
  decipher.setAuthTag(tag)
  // A tampered file fails at the end of the stream (the tag check), after
  // the bytes before it went out: the response is cut short, not served whole.
  const encrypted = createReadStream(file, { start: 12, end: size - 17 })
  encrypted.on('error', (error) => decipher.destroy(error))
  return { stream: encrypted.pipe(decipher), size: size - 28 }
}
