import crypto from 'crypto'
import path from 'path'
import { sql } from '../../lib/db'
import { readDecrypted, removeStored, storeEncrypted } from '../../lib/file-vault'
import { getPlanById } from '../../lib/plans'
import { publicBaseUrl } from '../password/password.service'
import { pickLang } from './requests.texts'

export const MAX_FILE_BYTES = 25 * 1024 * 1024
export const MAX_FILES_PER_REQUEST = 10
const MAX_BYTES_PER_REQUEST = 100 * 1024 * 1024
const DEFAULT_DAYS = 7
const MAX_DAYS = 30
// Files the app hasn't collected are deleted this long after arriving.
const KEEP_UNCOLLECTED_DAYS = 30

const ACCEPTED_EXTENSIONS = new Set([
  'pdf', 'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp',
  'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'txt',
])

export class RequestError extends Error {
  constructor(readonly status: number, message: string, readonly code?: string) {
    super(message)
  }
}

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex')
}

/// Creates a request (Vault). The link carries a token only its hash is
/// stored for, so it's returned once — the app keeps it to share again.
export async function createRequest(
  user: { id: string; plan: string },
  input: { title?: unknown; message?: unknown; language?: unknown; days?: unknown; albumId?: unknown },
  requestOrigin: string
) {
  if (!getPlanById(user.plan).features.includes('documentRequests')) {
    throw new RequestError(403, 'Document requests are included in the Vault plan')
  }
  const title = String(input.title ?? '').trim()
  if (!title || title.length > 200) {
    throw new RequestError(400, 'title is required (up to 200 characters)')
  }
  const message = String(input.message ?? '').trim().slice(0, 1000) || null
  const days = Math.min(MAX_DAYS, Math.max(1, Math.round(Number(input.days) || DEFAULT_DAYS)))
  const language = pickLang(input.language)
  const albumId = typeof input.albumId === 'string' && input.albumId ? input.albumId : null

  const id = crypto.randomUUID()
  const token = crypto.randomBytes(24).toString('base64url')
  const expiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000)
  await sql`
    INSERT INTO document_requests (id, user_id, token_hash, title, message, language, album_id, expires_at)
    VALUES (${id}, ${user.id}, ${hashToken(token)}, ${title}, ${message}, ${language}, ${albumId}, ${expiresAt})
  `
  return {
    id,
    url: `${publicBaseUrl(requestOrigin)}/r/${token}`,
    expiresAt,
  }
}

export async function listRequests(userId: string) {
  const requests = await sql`
    SELECT id, title, message, album_id, expires_at, closed_at, created_at
    FROM document_requests
    WHERE user_id = ${userId}
    ORDER BY created_at DESC
    LIMIT 50
  `
  const ids = requests.map((r) => r.id as string)
  const files = ids.length
    ? await sql`
        SELECT id, request_id, original_name, content_type, size_bytes, uploaded_at, received_at
        FROM document_request_files
        WHERE request_id IN ${sql(ids)}
        ORDER BY uploaded_at
      `
    : []
  const now = Date.now()
  return requests.map((r) => ({
    id: r.id as string,
    title: r.title as string,
    message: (r.message as string | null) ?? null,
    albumId: (r.album_id as string | null) ?? null,
    createdAt: r.created_at as Date,
    expiresAt: r.expires_at as Date,
    status: r.closed_at
      ? 'closed'
      : (r.expires_at as Date).getTime() <= now
        ? 'expired'
        : 'open',
    files: files
      .filter((f) => f.request_id === r.id)
      .map((f) => ({
        id: f.id as string,
        name: f.original_name as string,
        contentType: (f.content_type as string | null) ?? null,
        sizeBytes: Number(f.size_bytes),
        uploadedAt: f.uploaded_at as Date,
        receivedAt: (f.received_at as Date | null) ?? null,
      })),
  }))
}

async function ownedFile(userId: string, requestId: string, fileId: string) {
  const rows = await sql`
    SELECT f.id, f.original_name, f.content_type, f.stored_name
    FROM document_request_files f
    JOIN document_requests r ON r.id = f.request_id
    WHERE f.id = ${fileId} AND r.id = ${requestId} AND r.user_id = ${userId}
  `
  if (rows.length === 0) throw new RequestError(404, 'File not found')
  return rows[0]
}

export async function downloadFile(userId: string, requestId: string, fileId: string) {
  const row = await ownedFile(userId, requestId, fileId)
  const stored = row.stored_name as string | null
  if (!stored) throw new RequestError(410, 'File already collected')
  return {
    name: row.original_name as string,
    contentType: (row.content_type as string | null) ?? 'application/octet-stream',
    bytes: await readDecrypted(stored),
  }
}

/// The app has the file: delete it from the server.
export async function markReceived(userId: string, requestId: string, fileId: string) {
  const row = await ownedFile(userId, requestId, fileId)
  const stored = row.stored_name as string | null
  if (stored) await removeStored(stored)
  await sql`
    UPDATE document_request_files
    SET stored_name = NULL, received_at = COALESCE(received_at, NOW())
    WHERE id = ${fileId}
  `
}

export async function closeRequest(userId: string, requestId: string) {
  const result = await sql`
    UPDATE document_requests SET closed_at = COALESCE(closed_at, NOW())
    WHERE id = ${requestId} AND user_id = ${userId}
  `
  if (result.count === 0) throw new RequestError(404, 'Request not found')
}

export async function deleteRequest(userId: string, requestId: string) {
  const files = await sql`
    SELECT f.stored_name FROM document_request_files f
    JOIN document_requests r ON r.id = f.request_id
    WHERE r.id = ${requestId} AND r.user_id = ${userId} AND f.stored_name IS NOT NULL
  `
  for (const file of files) await removeStored(file.stored_name as string)
  const result = await sql`
    DELETE FROM document_requests WHERE id = ${requestId} AND user_id = ${userId}
  `
  if (result.count === 0) throw new RequestError(404, 'Request not found')
}

// ---- Public side: the person who was asked ------------------------------

/// The request a link points to, while it still takes files.
export async function openRequestByToken(token: string) {
  if (!/^[A-Za-z0-9_-]{20,64}$/.test(token)) return null
  const rows = await sql`
    SELECT r.id, r.title, r.message, r.language, r.expires_at, p.display_name
    FROM document_requests r
    LEFT JOIN profiles p ON p.id = r.user_id
    WHERE r.token_hash = ${hashToken(token)}
      AND r.closed_at IS NULL
      AND r.expires_at > NOW()
  `
  const row = rows[0]
  if (!row) return null
  return {
    id: row.id as string,
    title: row.title as string,
    message: (row.message as string | null) ?? null,
    language: pickLang(row.language),
    expiresAt: row.expires_at as Date,
    requesterName: ((row.display_name as string | null) ?? '').trim() || 'AllDocs',
  }
}

function cleanFileName(raw: unknown): string {
  const base = path.basename(String(raw ?? '')).replace(/[\u0000-\u001f\u007f/\\]/g, '').trim()
  return base.slice(0, 180) || 'documento'
}

export async function receiveUpload(
  token: string,
  rawName: unknown,
  contentType: string | undefined,
  body: unknown
) {
  const request = await openRequestByToken(token)
  if (!request) throw new RequestError(404, 'Request not available', 'invalid')
  if (!Buffer.isBuffer(body) || body.length === 0) {
    throw new RequestError(400, 'Empty file', 'failed')
  }
  if (body.length > MAX_FILE_BYTES) throw new RequestError(413, 'File too large', 'tooBig')
  const name = cleanFileName(rawName)
  const extension = name.includes('.') ? name.split('.').pop()!.toLowerCase() : ''
  if (!ACCEPTED_EXTENSIONS.has(extension)) {
    throw new RequestError(415, 'File type not accepted', 'badType')
  }
  const totals = await sql`
    SELECT COUNT(*) AS files, COALESCE(SUM(size_bytes), 0) AS bytes
    FROM document_request_files WHERE request_id = ${request.id}
  `
  if (
    Number(totals[0].files) >= MAX_FILES_PER_REQUEST ||
    Number(totals[0].bytes) + body.length > MAX_BYTES_PER_REQUEST
  ) {
    throw new RequestError(429, 'Too many files for this request', 'tooMany')
  }
  const stored = await storeEncrypted(body)
  await sql`
    INSERT INTO document_request_files (id, request_id, original_name, content_type, size_bytes, stored_name)
    VALUES (${crypto.randomUUID()}, ${request.id}, ${name}, ${contentType ?? null}, ${body.length}, ${stored})
  `
}

/// Deletes files no app collected within KEEP_UNCOLLECTED_DAYS, and
/// requests long past their expiry. Run on start and every hour.
export async function purgeOld() {
  const stale = await sql`
    SELECT id, stored_name FROM document_request_files
    WHERE stored_name IS NOT NULL
      AND uploaded_at < NOW() - make_interval(days => ${KEEP_UNCOLLECTED_DAYS})
  `
  for (const file of stale) {
    await removeStored(file.stored_name as string)
    await sql`UPDATE document_request_files SET stored_name = NULL WHERE id = ${file.id}`
  }
  const old = await sql`
    SELECT f.stored_name FROM document_request_files f
    JOIN document_requests r ON r.id = f.request_id
    WHERE r.expires_at < NOW() - make_interval(days => ${KEEP_UNCOLLECTED_DAYS * 2})
      AND f.stored_name IS NOT NULL
  `
  for (const file of old) await removeStored(file.stored_name as string)
  await sql`
    DELETE FROM document_requests
    WHERE expires_at < NOW() - make_interval(days => ${KEEP_UNCOLLECTED_DAYS * 2})
  `
}
