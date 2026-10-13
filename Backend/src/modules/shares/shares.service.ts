import crypto from 'crypto'
import path from 'path'
import { promisify } from 'util'
import { sql } from '../../lib/db'
import { readDecrypted, removeStored, storeEncrypted } from '../../lib/file-vault'
import { getPlanById } from '../../lib/plans'
import { LINK_TOKEN_PATTERN, linksBaseUrl } from '../../lib/public-links'
import { pickLang } from '../requests/requests.texts'

export const MAX_SHARE_BYTES = 50 * 1024 * 1024
const DEFAULT_DAYS = 7
const MAX_DAYS = 30
// Wrong codes tried before the link locks for good.
export const MAX_CODE_ATTEMPTS = 10
// Rows are kept this long after the link stopped working, so the owner
// still sees what happened to it; the file itself goes right away.
const KEEP_ENDED_DAYS = 30

const CONTENT_TYPES: Record<string, string> = {
  pdf: 'application/pdf',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  heic: 'image/heic',
  heif: 'image/heif',
  txt: 'text/plain; charset=utf-8',
  doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ppt: 'application/vnd.ms-powerpoint',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  odt: 'application/vnd.oasis.opendocument.text',
  ods: 'application/vnd.oasis.opendocument.spreadsheet',
}

// What a browser can show by itself; everything else is downloaded.
const VIEWABLE = new Set(['pdf', 'jpg', 'jpeg', 'png', 'webp', 'txt'])

export class ShareError extends Error {
  constructor(readonly status: number, message: string, readonly code?: string) {
    super(message)
  }
}

export type ShareStatus = 'active' | 'expired' | 'revoked' | 'locked' | 'used'

const scrypt = promisify(crypto.scrypt) as (
  password: string,
  salt: Buffer,
  keylen: number
) => Promise<Buffer>

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex')
}

async function hashCode(code: string): Promise<string> {
  const salt = crypto.randomBytes(16)
  const hash = await scrypt(code, salt, 32)
  return `${salt.toString('hex')}:${hash.toString('hex')}`
}

async function codeMatches(code: string, stored: string): Promise<boolean> {
  const [salt, hash] = stored.split(':')
  if (!salt || !hash) return false
  const candidate = await scrypt(code, Buffer.from(salt, 'hex'), 32)
  const expected = Buffer.from(hash, 'hex')
  return expected.length === candidate.length && crypto.timingSafeEqual(candidate, expected)
}

function extensionOf(name: string): string {
  return name.includes('.') ? name.split('.').pop()!.toLowerCase() : ''
}

function cleanFileName(raw: unknown): string {
  const base = path.basename(String(raw ?? '')).replace(/[\u0000-\u001f\u007f/\\]/g, '').trim()
  return base.slice(0, 180)
}

function statusOf(row: Record<string, unknown>): ShareStatus {
  if (row.revoked_at) return 'revoked'
  if (Number(row.failed_attempts) >= MAX_CODE_ATTEMPTS) return 'locked'
  if (row.max_views != null && Number(row.view_count) >= Number(row.max_views)) return 'used'
  if ((row.expires_at as Date).getTime() <= Date.now()) return 'expired'
  return 'active'
}

/// Creates a share (Vault) from the file in [body]. [meta] comes from the
/// X-Share-Meta header. The link carries a token only its hash is stored
/// for, so it's returned once — the app keeps it to share again.
export async function createShare(
  user: { id: string; plan: string },
  meta: {
    title?: unknown
    fileName?: unknown
    days?: unknown
    code?: unknown
    maxViews?: unknown
    language?: unknown
  },
  body: unknown,
  requestOrigin: string
) {
  if (!getPlanById(user.plan).features.includes('secureSharing')) {
    throw new ShareError(403, 'Secure sharing is included in the Vault plan')
  }
  if (!Buffer.isBuffer(body) || body.length === 0) {
    throw new ShareError(400, 'The request body must be the file')
  }
  if (body.length > MAX_SHARE_BYTES) throw new ShareError(413, 'File too large', 'tooBig')
  const fileName = cleanFileName(meta.fileName)
  const extension = extensionOf(fileName)
  const contentType = CONTENT_TYPES[extension]
  if (!fileName || !contentType) {
    throw new ShareError(415, 'File type not accepted', 'badType')
  }
  const title = String(meta.title ?? '').trim().slice(0, 200) || fileName
  const days = Math.min(MAX_DAYS, Math.max(1, Math.round(Number(meta.days) || DEFAULT_DAYS)))
  const code = meta.code == null ? '' : String(meta.code).trim()
  if (code && !/^\d{4,8}$/.test(code)) {
    throw new ShareError(400, 'code must be 4 to 8 digits')
  }
  const maxViewsNumber = Math.round(Number(meta.maxViews))
  const maxViews = maxViewsNumber >= 1 ? Math.min(maxViewsNumber, 1000) : null
  const language = pickLang(meta.language)

  const id = crypto.randomUUID()
  const token = crypto.randomBytes(16).toString('base64url')
  const expiresAt = new Date(Date.now() + days * 24 * 60 * 60 * 1000)
  const stored = await storeEncrypted(body)
  try {
    await sql`
      INSERT INTO document_shares (
        id, user_id, token_hash, title, file_name, content_type, size_bytes,
        stored_name, language, code_hash, max_views, expires_at
      ) VALUES (
        ${id}, ${user.id}, ${hashToken(token)}, ${title}, ${fileName}, ${contentType},
        ${body.length}, ${stored}, ${language}, ${code ? await hashCode(code) : null},
        ${maxViews}, ${expiresAt}
      )
    `
  } catch (error) {
    await removeStored(stored)
    throw error
  }
  return { id, url: `${linksBaseUrl(requestOrigin)}/s/${token}`, expiresAt }
}

export async function listShares(userId: string) {
  const rows = await sql`
    SELECT id, title, file_name, size_bytes, code_hash, failed_attempts, max_views,
      view_count, last_viewed_at, expires_at, revoked_at, created_at
    FROM document_shares
    WHERE user_id = ${userId}
    ORDER BY created_at DESC
    LIMIT 100
  `
  return rows.map((row) => ({
    id: row.id as string,
    title: row.title as string,
    fileName: row.file_name as string,
    sizeBytes: Number(row.size_bytes),
    hasCode: row.code_hash != null,
    maxViews: row.max_views == null ? null : Number(row.max_views),
    viewCount: Number(row.view_count),
    lastViewedAt: (row.last_viewed_at as Date | null) ?? null,
    createdAt: row.created_at as Date,
    expiresAt: row.expires_at as Date,
    status: statusOf(row),
  }))
}

/// The link stops working now and the file is deleted.
export async function revokeShare(userId: string, shareId: string) {
  const rows = await sql`
    UPDATE document_shares SET revoked_at = COALESCE(revoked_at, NOW())
    WHERE id = ${shareId} AND user_id = ${userId}
    RETURNING stored_name
  `
  if (rows.length === 0) throw new ShareError(404, 'Share not found')
  await dropFile(shareId, rows[0].stored_name as string | null)
}

export async function deleteShare(userId: string, shareId: string) {
  const rows = await sql`
    DELETE FROM document_shares WHERE id = ${shareId} AND user_id = ${userId}
    RETURNING stored_name
  `
  if (rows.length === 0) throw new ShareError(404, 'Share not found')
  if (rows[0].stored_name) await removeStored(rows[0].stored_name as string)
}

async function dropFile(shareId: string, storedName: string | null) {
  if (!storedName) return
  await removeStored(storedName)
  await sql`UPDATE document_shares SET stored_name = NULL WHERE id = ${shareId}`
}

// ---- Public side: whoever has the link ----------------------------------

export type OpenShare = {
  id: string
  title: string
  fileName: string
  sizeBytes: number
  language: ReturnType<typeof pickLang>
  expiresAt: Date
  ownerName: string
  needsCode: boolean
  viewsLeft: number | null
  attemptsLeft: number
  status: ShareStatus
}

/// The share a link points to, whatever its status; null for an unknown
/// token or one whose file is gone.
export async function findShareByToken(token: string): Promise<OpenShare | null> {
  if (!LINK_TOKEN_PATTERN.test(token)) return null
  const rows = await sql`
    SELECT s.*, p.display_name
    FROM document_shares s
    LEFT JOIN profiles p ON p.id = s.user_id
    WHERE s.token_hash = ${hashToken(token)}
  `
  const row = rows[0]
  if (!row) return null
  const status = statusOf(row)
  if (status === 'active' && !row.stored_name) return null
  return {
    id: row.id as string,
    title: row.title as string,
    fileName: row.file_name as string,
    sizeBytes: Number(row.size_bytes),
    language: pickLang(row.language),
    expiresAt: row.expires_at as Date,
    ownerName: ((row.display_name as string | null) ?? '').trim() || 'AllDocs',
    needsCode: row.code_hash != null,
    viewsLeft: row.max_views == null ? null : Number(row.max_views) - Number(row.view_count),
    attemptsLeft: MAX_CODE_ATTEMPTS - Number(row.failed_attempts),
    status,
  }
}

/// The file, when the link still works and [code] is right. Counts a view;
/// a wrong code counts an attempt (ShareError 'wrongCode' / 'locked').
export async function openShareFile(token: string, code: unknown, download: boolean) {
  if (!LINK_TOKEN_PATTERN.test(token)) throw new ShareError(404, 'Not found', 'invalid')
  const rows = await sql`
    SELECT * FROM document_shares WHERE token_hash = ${hashToken(token)}
  `
  const row = rows[0]
  if (!row) throw new ShareError(404, 'Not found', 'invalid')
  const status = statusOf(row)
  if (status === 'locked') throw new ShareError(403, 'Locked', 'locked')
  if (status !== 'active' || !row.stored_name) {
    throw new ShareError(404, 'Not available', 'invalid')
  }

  if (row.code_hash) {
    const given = String(code ?? '').trim()
    if (!given || !(await codeMatches(given, row.code_hash as string))) {
      const updated = await sql`
        UPDATE document_shares SET failed_attempts = failed_attempts + 1
        WHERE id = ${row.id}
        RETURNING failed_attempts
      `
      const attempts = Number(updated[0].failed_attempts)
      if (attempts >= MAX_CODE_ATTEMPTS) {
        await dropFile(row.id as string, row.stored_name as string)
        throw new ShareError(403, 'Locked', 'locked')
      }
      throw new ShareError(403, 'Wrong code', 'wrongCode')
    }
  }

  // Counted atomically, so a last view can't be used twice at once.
  const counted = await sql`
    UPDATE document_shares
    SET view_count = view_count + 1, last_viewed_at = NOW()
    WHERE id = ${row.id}
      AND (max_views IS NULL OR view_count < max_views)
      AND revoked_at IS NULL
      AND expires_at > NOW()
    RETURNING view_count, max_views
  `
  if (counted.length === 0) throw new ShareError(404, 'Not available', 'invalid')
  const bytes = await readDecrypted(row.stored_name as string)
  const last =
    counted[0].max_views != null && Number(counted[0].view_count) >= Number(counted[0].max_views)
  if (last) await dropFile(row.id as string, row.stored_name as string)

  const extension = extensionOf(row.file_name as string)
  return {
    bytes,
    fileName: row.file_name as string,
    contentType: row.content_type as string,
    inline: !download && VIEWABLE.has(extension),
  }
}

/// Deletes the files of links that stopped working, and rows long past
/// that. Run on start and every hour.
export async function purgeOld() {
  const ended = await sql`
    SELECT id, stored_name FROM document_shares
    WHERE stored_name IS NOT NULL
      AND (expires_at <= NOW() OR revoked_at IS NOT NULL)
  `
  for (const row of ended) await dropFile(row.id as string, row.stored_name as string)
  await sql`
    DELETE FROM document_shares
    WHERE expires_at < NOW() - make_interval(days => ${KEEP_ENDED_DAYS})
      AND stored_name IS NULL
  `
}
