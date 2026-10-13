import crypto from 'crypto'
import { createReadStream, createWriteStream } from 'fs'
import { mkdir, rename, rm, stat } from 'fs/promises'
import path from 'path'
import type { Readable } from 'stream'
import { pipeline } from 'stream/promises'
import { Transform } from 'stream'

// Device sync files, stored as they arrive: the phone already encrypted
// them with a key the server never sees. Streamed to and from disk, so a
// large document never sits in memory. Lives under UPLOADS_DIR (a
// persistent volume in production).

const DIR = path.join(
  process.env.UPLOADS_DIR?.trim() || path.resolve(process.cwd(), 'data/uploads'),
  'sync'
)

export class BlobTooLargeError extends Error {}

function pathFor(name: string): string {
  if (!/^[0-9a-f-]{36}$/.test(name)) throw new Error('Invalid stored blob name')
  return path.join(DIR, name)
}

/// Writes [source] to a new file, failing once it passes [maxBytes].
/// Returns the name to read or delete it by, and its size.
export async function saveStream(
  source: Readable,
  maxBytes: number
): Promise<{ name: string; size: number }> {
  await mkdir(DIR, { recursive: true })
  const name = crypto.randomUUID()
  const temp = `${pathFor(name)}.part`
  let size = 0
  const limit = new Transform({
    transform(chunk: Buffer, _encoding, callback) {
      size += chunk.length
      if (size > maxBytes) callback(new BlobTooLargeError('Blob too large'))
      else callback(null, chunk)
    },
  })
  try {
    await pipeline(source, limit, createWriteStream(temp))
    await rename(temp, pathFor(name))
  } catch (error) {
    await rm(temp, { force: true })
    throw error
  }
  return { name, size }
}

export async function openBlob(name: string): Promise<{ stream: Readable; size: number }> {
  const file = pathFor(name)
  const info = await stat(file)
  return { stream: createReadStream(file), size: info.size }
}

export async function removeBlob(name: string): Promise<void> {
  await rm(pathFor(name), { force: true })
}
