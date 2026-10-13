import crypto from 'crypto'
import type { Readable } from 'stream'
import { BlobTooLargeError, openBlob, removeBlob, saveStream } from '../../lib/blob-store'
import { sql } from '../../lib/db'
import { getPlanById } from '../../lib/plans'
import { notifyDevices } from './sync.events'

// Device sync relay (Vault). The phones do the syncing: each one sends its
// library's changes as encrypted batches, numbered here in one sequence per
// account, and fetches the others'. Document files travel as encrypted
// blobs that wait only until every device that needs them has them. The
// key never reaches the server — devices get it from each other's QR code.

export const MAX_CHANGE_BYTES = 8 * 1024 * 1024
export const MAX_BLOB_BYTES = 1024 * 1024 * 1024
export const MAX_SNAPSHOT_BYTES = 256 * 1024 * 1024
// Files waiting on the server per account, all together. A device sending
// more than this waits until the others have caught up.
const MAX_PENDING_BYTES = 10 * 1024 * 1024 * 1024
const KEEP_DAYS = 30
const SNAPSHOT_KEEP_DAYS = 7
const PAIRING_MINUTES = 10
const PAGE_SIZE = 200
const BLOB_ID = /^[0-9a-f]{64}$/
const KEY_CHECK = /^[0-9a-f]{64}$/

export class SyncError extends Error {
  constructor(readonly status: number, message: string, readonly code?: string) {
    super(message)
  }
}

type User = { id: string; plan: string; deviceId?: string | null }

function hash(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex')
}

export function requireSync(user: User) {
  if (!getPlanById(user.plan).features.includes('deviceSync')) {
    throw new SyncError(403, 'Device sync is included in the Vault plan', 'notIncluded')
  }
}

/// The calling device (X-Sync-Device), while it's still part of the
/// account's sync; also marks it as seen.
export async function deviceFor(user: User, deviceId: string | undefined) {
  const rows = deviceId
    ? await sql`
        UPDATE sync_devices SET last_seen_at = NOW()
        WHERE id = ${deviceId} AND user_id = ${user.id}
        RETURNING id, cursor, needs_snapshot
      `
    : []
  if (rows.length === 0) {
    throw new SyncError(403, 'This device is not part of sync', 'deviceRemoved')
  }
  return {
    id: rows[0].id as string,
    cursor: Number(rows[0].cursor),
    needsSnapshot: rows[0].needs_snapshot === true,
  }
}

export async function status(user: User) {
  const circles = await sql`SELECT key_check FROM sync_circles WHERE user_id = ${user.id}`
  const devices = await sql`
    SELECT id, name, platform, created_at, last_seen_at, needs_snapshot
    FROM sync_devices WHERE user_id = ${user.id}
    ORDER BY created_at
  `
  return {
    enabled: circles.length > 0,
    keyCheck: (circles[0]?.key_check as string | undefined) ?? null,
    maxDevices: getPlanById(user.plan).maxDevices,
    devices: devices.map((d) => ({
      id: d.id as string,
      name: d.name as string,
      platform: (d.platform as string | null) ?? null,
      createdAt: d.created_at as Date,
      lastSeenAt: d.last_seen_at as Date,
      waitingForLibrary: d.needs_snapshot === true,
    })),
  }
}

/// Adds this phone to the account's sync: the first device starts it (and
/// sets the key check); the next ones need a pairing code from a device
/// already in, and the same key.
export async function registerDevice(
  user: User,
  input: { name?: unknown; platform?: unknown; keyCheck?: unknown; pairingCode?: unknown }
) {
  requireSync(user)
  const name = String(input.name ?? '').trim().slice(0, 80) || 'AllDocs'
  const platform = String(input.platform ?? '').trim().slice(0, 20) || null
  const keyCheck = String(input.keyCheck ?? '').toLowerCase()
  if (!KEY_CHECK.test(keyCheck)) throw new SyncError(400, 'keyCheck is required')
  const pairingCode = typeof input.pairingCode === 'string' ? input.pairingCode : ''
  const maxDevices = getPlanById(user.plan).maxDevices
  const id = crypto.randomUUID()
  const sessionDeviceId = user.deviceId ?? null

  // This same phone was in sync before (reinstalled, signed in again):
  // its old entry goes, instead of taking another of the plan's places.
  // If it was the only one, the old sync ends and this one starts anew.
  if (sessionDeviceId) await releaseSessionDevices(user.id, [sessionDeviceId])

  const registered = await sql.begin(async (tx) => {
    await tx`SELECT pg_advisory_xact_lock(hashtext(${'sync:' + user.id}))`
    const circles = await tx`SELECT key_check FROM sync_circles WHERE user_id = ${user.id}`
    if (circles.length === 0) {
      if (pairingCode) throw new SyncError(409, 'Sync was turned off on the other device', 'noCircle')
      await tx`INSERT INTO sync_circles (user_id, key_check) VALUES (${user.id}, ${keyCheck})`
      await tx`
        INSERT INTO sync_devices (id, user_id, name, platform, session_device_id)
        VALUES (${id}, ${user.id}, ${name}, ${platform}, ${sessionDeviceId})
      `
      return { deviceId: id, first: true }
    }

    if (!pairingCode) throw new SyncError(409, 'Sync is already on: join with a code', 'needsPairing')
    const pairings = await tx`
      SELECT code_hash FROM sync_pairings
      WHERE code_hash = ${hash(pairingCode)} AND user_id = ${user.id}
        AND device_id IS NULL AND expires_at > NOW()
    `
    if (pairings.length === 0) throw new SyncError(409, 'The code expired or was used', 'badCode')
    if (circles[0].key_check !== keyCheck) {
      throw new SyncError(409, 'The code is from another sync', 'wrongKey')
    }
    const count = await tx`SELECT COUNT(*)::int AS n FROM sync_devices WHERE user_id = ${user.id}`
    if (Number(count[0].n) >= maxDevices) {
      throw new SyncError(409, `Up to ${maxDevices} devices`, 'tooMany')
    }
    await tx`
      INSERT INTO sync_devices (id, user_id, name, platform, needs_snapshot, session_device_id)
      VALUES (${id}, ${user.id}, ${name}, ${platform}, TRUE, ${sessionDeviceId})
    `
    await tx`UPDATE sync_pairings SET device_id = ${id} WHERE code_hash = ${hash(pairingCode)}`
    return { deviceId: id, first: false }
  })
  // The others send the newcomer the library.
  notifyDevices(user.id, id)
  return registered
}

/// Takes a device out of sync (itself, or another one of the account's).
/// The last one out ends the account's sync and deletes everything left.
export async function removeDevice(user: User, deviceId: string) {
  const removed = await sql`
    DELETE FROM sync_devices WHERE id = ${deviceId} AND user_id = ${user.id} RETURNING id
  `
  if (removed.length === 0) throw new SyncError(404, 'Device not found')
  await sql`DELETE FROM sync_blob_needs WHERE user_id = ${user.id} AND device_id = ${deviceId}`
  await sql`DELETE FROM sync_blob_requests WHERE user_id = ${user.id} AND device_id = ${deviceId}`
  const snapshots = await sql`
    DELETE FROM sync_snapshots WHERE device_id = ${deviceId} RETURNING stored_name
  `
  for (const s of snapshots) await removeBlob(s.stored_name as string)

  notifyDevices(user.id)
  const left = await sql`SELECT COUNT(*)::int AS n FROM sync_devices WHERE user_id = ${user.id}`
  if (Number(left[0].n) === 0) {
    await endSync(user.id)
  } else {
    await dropUnneededBlobs(user.id)
  }
}

/// The phones whose sessions ended ([sessionDeviceIds]; null: all of the
/// account's) leave sync, freeing their places.
export async function releaseSessionDevices(userId: string, sessionDeviceIds: string[] | null) {
  const rows = sessionDeviceIds === null
    ? await sql`SELECT id FROM sync_devices WHERE user_id = ${userId}`
    : sessionDeviceIds.length === 0
      ? []
      : await sql`
          SELECT id FROM sync_devices
          WHERE user_id = ${userId} AND session_device_id IN ${sql(sessionDeviceIds)}
        `
  for (const row of rows) {
    await removeDevice({ id: userId, plan: 'free' }, row.id as string).catch((error) => {
      if (!(error instanceof SyncError)) throw error
    })
  }
}

async function endSync(userId: string) {
  const blobs = await sql`DELETE FROM sync_blobs WHERE user_id = ${userId} RETURNING stored_name`
  for (const b of blobs) await removeBlob(b.stored_name as string)
  const snapshots = await sql`DELETE FROM sync_snapshots WHERE user_id = ${userId} RETURNING stored_name`
  for (const s of snapshots) await removeBlob(s.stored_name as string)
  await sql`DELETE FROM sync_blob_needs WHERE user_id = ${userId}`
  await sql`DELETE FROM sync_blob_requests WHERE user_id = ${userId}`
  await sql`DELETE FROM sync_changes WHERE user_id = ${userId}`
  await sql`DELETE FROM sync_pairings WHERE user_id = ${userId}`
  await sql`DELETE FROM sync_circles WHERE user_id = ${userId}`
}

// ---- Pairing (QR) --------------------------------------------------------

/// A one-time code for the QR a device shows to bring in another one.
export async function createPairing(user: User, deviceId: string) {
  const code = crypto.randomBytes(16).toString('base64url')
  const expiresAt = new Date(Date.now() + PAIRING_MINUTES * 60 * 1000)
  await sql`
    INSERT INTO sync_pairings (code_hash, user_id, created_by, expires_at)
    VALUES (${hash(code)}, ${user.id}, ${deviceId}, ${expiresAt})
  `
  return { code, expiresAt }
}

/// Whether a device joined with [code] yet (the QR screen waits on it).
export async function pairingStatus(user: User, code: unknown) {
  const rows = await sql`
    SELECT p.device_id, p.expires_at, d.name
    FROM sync_pairings p
    LEFT JOIN sync_devices d ON d.id = p.device_id
    WHERE p.code_hash = ${hash(String(code ?? ''))} AND p.user_id = ${user.id}
  `
  const row = rows[0]
  if (!row) throw new SyncError(404, 'Unknown code')
  return {
    joined: row.device_id != null,
    deviceName: (row.name as string | null) ?? null,
    expired: (row.expires_at as Date).getTime() <= Date.now() && row.device_id == null,
  }
}

// ---- Changes -------------------------------------------------------------

/// Everything a device has to do next: the changes after [after] (which
/// also acknowledges up to there), blobs the others asked for, devices
/// waiting for a snapshot, and whether its own snapshot is ready.
export async function pull(user: User, device: { id: string; needsSnapshot: boolean }, after: number) {
  const circles = await sql`SELECT purged_upto FROM sync_circles WHERE user_id = ${user.id}`
  if (circles.length === 0) throw new SyncError(403, 'Sync is off', 'deviceRemoved')
  const purgedUpto = Number(circles[0].purged_upto)

  const snapshotReady =
    (await sql`SELECT 1 FROM sync_snapshots WHERE device_id = ${device.id}`).length > 0
  let needsSnapshot = device.needsSnapshot
  if (!needsSnapshot && after < purgedUpto) {
    // Too far behind: the changes it misses are gone.
    await sql`UPDATE sync_devices SET needs_snapshot = TRUE, cursor = 0 WHERE id = ${device.id}`
    needsSnapshot = true
  }

  let changes: { seq: number; deviceId: string; payload: string }[] = []
  let hasMore = false
  if (!needsSnapshot) {
    await sql`
      UPDATE sync_devices SET cursor = GREATEST(cursor, ${after}) WHERE id = ${device.id}
    `
    const rows = await sql`
      SELECT seq, device_id, payload FROM sync_changes
      WHERE user_id = ${user.id} AND seq > ${after} AND device_id <> ${device.id}
      ORDER BY seq
      LIMIT ${PAGE_SIZE + 1}
    `
    hasMore = rows.length > PAGE_SIZE
    changes = rows.slice(0, PAGE_SIZE).map((r) => ({
      seq: Number(r.seq),
      deviceId: r.device_id as string,
      payload: Buffer.from(r.payload as Uint8Array).toString('base64'),
    }))
  }
  const latest = await sql`
    SELECT COALESCE(MAX(seq), 0) AS seq FROM sync_changes WHERE user_id = ${user.id}
  `
  const requested = await sql`
    SELECT DISTINCT r.blob_id FROM sync_blob_requests r
    WHERE r.user_id = ${user.id} AND r.device_id <> ${device.id}
      AND NOT EXISTS (
        SELECT 1 FROM sync_blobs b WHERE b.user_id = r.user_id AND b.blob_id = r.blob_id
      )
    LIMIT 500
  `
  const waiting = needsSnapshot
    ? []
    : await sql`
        SELECT d.id FROM sync_devices d
        WHERE d.user_id = ${user.id} AND d.needs_snapshot AND d.id <> ${device.id}
          AND NOT EXISTS (SELECT 1 FROM sync_snapshots s WHERE s.device_id = d.id)
      `
  const others = await sql`
    SELECT COUNT(*)::int AS n FROM sync_devices WHERE user_id = ${user.id} AND id <> ${device.id}
  `
  return {
    changes,
    hasMore,
    otherDevices: Number(others[0].n),
    latest: Math.max(Number(latest[0].seq), purgedUpto),
    needsSnapshot,
    snapshotReady,
    requestedBlobs: requested.map((r) => r.blob_id as string),
    snapshotFor: waiting.map((d) => d.id as string),
  }
}

/// Adds a batch after [baseSeq] — refused ('behind') when another device
/// added one since, so every device applies them in the same order.
export async function push(user: User, deviceId: string, baseSeq: number, body: unknown) {
  if (!Buffer.isBuffer(body) || body.length === 0) throw new SyncError(400, 'Empty batch')
  if (body.length > MAX_CHANGE_BYTES) throw new SyncError(413, 'Batch too large', 'tooBig')
  const result = await sql.begin(async (tx) => {
    await tx`SELECT pg_advisory_xact_lock(hashtext(${'sync:' + user.id}))`
    const latest = await tx`
      SELECT COALESCE(MAX(seq), 0) AS seq FROM sync_changes WHERE user_id = ${user.id}
    `
    const circles = await tx`SELECT purged_upto FROM sync_circles WHERE user_id = ${user.id}`
    const newest = Math.max(Number(latest[0].seq), Number(circles[0]?.purged_upto ?? 0))
    if (newest > baseSeq) throw new SyncError(409, 'Pull first', 'behind')
    const rows = await tx`
      INSERT INTO sync_changes (user_id, device_id, payload)
      VALUES (${user.id}, ${deviceId}, ${body})
      RETURNING seq
    `
    const seq = Number(rows[0].seq)
    await tx`UPDATE sync_devices SET cursor = ${seq} WHERE id = ${deviceId}`
    return { seq }
  })
  notifyDevices(user.id, deviceId)
  return result
}

/// Whether there are changes after [after] for this device to pull.
export async function hasChangesAfter(user: User, deviceId: string, after: number) {
  const rows = await sql`
    SELECT 1 FROM sync_changes
    WHERE user_id = ${user.id} AND seq > ${after} AND device_id <> ${deviceId}
    LIMIT 1
  `
  return rows.length > 0
}

// ---- Blobs (document files) ---------------------------------------------

function checkBlobId(blobId: string) {
  if (!BLOB_ID.test(blobId)) throw new SyncError(400, 'Invalid blob id')
}

/// Which of [ids] are already on the server.
export async function existingBlobs(user: User, ids: unknown) {
  const list = Array.isArray(ids) ? ids.filter((id) => typeof id === 'string' && BLOB_ID.test(id)) : []
  if (list.length === 0) return { existing: [] as string[] }
  const rows = await sql`
    SELECT blob_id FROM sync_blobs WHERE user_id = ${user.id} AND blob_id IN ${sql(list.slice(0, 1000))}
  `
  return { existing: rows.map((r) => r.blob_id as string) }
}

/// Stores a blob a device sent. [everyone]: every other device needs it (a
/// new or changed document); otherwise only the devices that asked for it.
export async function putBlob(
  user: User,
  deviceId: string,
  blobId: string,
  everyone: boolean,
  declaredSize: number,
  body: Readable
) {
  checkBlobId(blobId)
  const existing = await sql`
    SELECT 1 FROM sync_blobs WHERE user_id = ${user.id} AND blob_id = ${blobId}
  `
  if (existing.length === 0) {
    const pending = await sql`
      SELECT COALESCE(SUM(size_bytes), 0) AS bytes FROM sync_blobs WHERE user_id = ${user.id}
    `
    if (Number(pending[0].bytes) + Math.max(0, declaredSize) > MAX_PENDING_BYTES) {
      body.resume()
      throw new SyncError(507, 'Too much waiting on the server; try later', 'quota')
    }
    let saved: { name: string; size: number }
    try {
      saved = await saveStream(body, MAX_BLOB_BYTES)
    } catch (error) {
      if (error instanceof BlobTooLargeError) throw new SyncError(413, 'File too large', 'tooBig')
      throw error
    }
    const inserted = await sql`
      INSERT INTO sync_blobs (user_id, blob_id, stored_name, size_bytes)
      VALUES (${user.id}, ${blobId}, ${saved.name}, ${saved.size})
      ON CONFLICT DO NOTHING
      RETURNING blob_id
    `
    // Sent twice at once: keep the first.
    if (inserted.length === 0) await removeBlob(saved.name)
  } else {
    body.resume()
  }

  if (everyone) {
    await sql`
      INSERT INTO sync_blob_needs (user_id, blob_id, device_id)
      SELECT ${user.id}, ${blobId}, id FROM sync_devices
      WHERE user_id = ${user.id} AND id <> ${deviceId}
      ON CONFLICT DO NOTHING
    `
  }
  await sql`
    INSERT INTO sync_blob_needs (user_id, blob_id, device_id)
    SELECT user_id, blob_id, device_id FROM sync_blob_requests
    WHERE user_id = ${user.id} AND blob_id = ${blobId}
    ON CONFLICT DO NOTHING
  `
  await sql`DELETE FROM sync_blob_requests WHERE user_id = ${user.id} AND blob_id = ${blobId}`
  await dropUnneededBlobs(user.id, blobId)
  // Whoever needs it can download it now.
  notifyDevices(user.id, deviceId)
}

export async function getBlob(user: User, blobId: string) {
  checkBlobId(blobId)
  const rows = await sql`
    SELECT stored_name FROM sync_blobs WHERE user_id = ${user.id} AND blob_id = ${blobId}
  `
  if (rows.length === 0) throw new SyncError(404, 'Not on the server', 'missing')
  return openBlob(rows[0].stored_name as string)
}

/// This device has the blob now; it's deleted once no device needs it.
export async function ackBlob(user: User, deviceId: string, blobId: string) {
  checkBlobId(blobId)
  await sql`
    DELETE FROM sync_blob_needs
    WHERE user_id = ${user.id} AND blob_id = ${blobId} AND device_id = ${deviceId}
  `
  await sql`
    DELETE FROM sync_blob_requests
    WHERE user_id = ${user.id} AND blob_id = ${blobId} AND device_id = ${deviceId}
  `
  await dropUnneededBlobs(user.id, blobId)
}

/// Files this device is missing: the ones already on the server are
/// marked as needed by it, the others asked of the other devices.
export async function requestBlobs(user: User, deviceId: string, ids: unknown) {
  const list = Array.isArray(ids)
    ? [...new Set(ids.filter((id) => typeof id === 'string' && BLOB_ID.test(id)))].slice(0, 1000)
    : []
  if (list.length === 0) return { available: [] as string[] }
  const present = await sql`
    SELECT blob_id FROM sync_blobs WHERE user_id = ${user.id} AND blob_id IN ${sql(list)}
  `
  const available = new Set(present.map((r) => r.blob_id as string))
  for (const blobId of list) {
    if (available.has(blobId)) {
      await sql`
        INSERT INTO sync_blob_needs (user_id, blob_id, device_id)
        VALUES (${user.id}, ${blobId}, ${deviceId}) ON CONFLICT DO NOTHING
      `
    } else {
      await sql`
        INSERT INTO sync_blob_requests (user_id, blob_id, device_id)
        VALUES (${user.id}, ${blobId}, ${deviceId}) ON CONFLICT DO NOTHING
      `
    }
  }
  // The devices that have the missing files send them.
  if (available.size < list.length) notifyDevices(user.id, deviceId)
  return { available: [...available] }
}

async function dropUnneededBlobs(userId: string, blobId?: string) {
  const rows = await sql`
    DELETE FROM sync_blobs b
    WHERE b.user_id = ${userId}
      ${blobId ? sql`AND b.blob_id = ${blobId}` : sql``}
      AND NOT EXISTS (
        SELECT 1 FROM sync_blob_needs n
        JOIN sync_devices d ON d.id = n.device_id
        WHERE n.user_id = b.user_id AND n.blob_id = b.blob_id
      )
    RETURNING stored_name
  `
  for (const row of rows) await removeBlob(row.stored_name as string)
}

// ---- Snapshots (the whole library, for a device that joins) -------------

export async function putSnapshot(
  user: User,
  targetDeviceId: string,
  uptoSeq: number,
  body: Readable
) {
  const targets = await sql`
    SELECT id FROM sync_devices
    WHERE id = ${targetDeviceId} AND user_id = ${user.id} AND needs_snapshot
  `
  if (targets.length === 0) {
    body.resume()
    throw new SyncError(409, 'That device does not need a snapshot', 'notNeeded')
  }
  let saved: { name: string; size: number }
  try {
    saved = await saveStream(body, MAX_SNAPSHOT_BYTES)
  } catch (error) {
    if (error instanceof BlobTooLargeError) throw new SyncError(413, 'Snapshot too large', 'tooBig')
    throw error
  }
  const previous = await sql`
    DELETE FROM sync_snapshots WHERE device_id = ${targetDeviceId} RETURNING stored_name
  `
  for (const p of previous) await removeBlob(p.stored_name as string)
  await sql`
    INSERT INTO sync_snapshots (device_id, user_id, upto_seq, stored_name, size_bytes)
    VALUES (${targetDeviceId}, ${user.id}, ${uptoSeq}, ${saved.name}, ${saved.size})
  `
  notifyDevices(user.id)
}

export async function getSnapshot(deviceId: string) {
  const rows = await sql`SELECT upto_seq, stored_name FROM sync_snapshots WHERE device_id = ${deviceId}`
  if (rows.length === 0) throw new SyncError(404, 'No snapshot yet', 'missing')
  return { uptoSeq: Number(rows[0].upto_seq), ...(await openBlob(rows[0].stored_name as string)) }
}

/// The device loaded its snapshot: it carries on from [uptoSeq].
export async function ackSnapshot(deviceId: string) {
  const rows = await sql`
    DELETE FROM sync_snapshots WHERE device_id = ${deviceId} RETURNING upto_seq, stored_name
  `
  if (rows.length === 0) throw new SyncError(404, 'No snapshot', 'missing')
  await removeBlob(rows[0].stored_name as string)
  await sql`
    UPDATE sync_devices SET needs_snapshot = FALSE, cursor = ${Number(rows[0].upto_seq)}
    WHERE id = ${deviceId}
  `
}

// ---- Cleanup -------------------------------------------------------------

/// Deletes changes every device has (or that are too old), blobs and
/// requests nobody collected in time, stale snapshots and pairing codes.
/// Run on start and every hour.
export async function purgeOld() {
  const circles = await sql`SELECT user_id FROM sync_circles`
  for (const circle of circles) {
    const userId = circle.user_id as string
    const cursors = await sql`
      SELECT COALESCE(MIN(cursor), 0) AS min FROM sync_devices WHERE user_id = ${userId}
    `
    const deleted = await sql`
      DELETE FROM sync_changes
      WHERE user_id = ${userId}
        AND (seq <= ${Number(cursors[0].min)}
          OR created_at < NOW() - make_interval(days => ${KEEP_DAYS}))
      RETURNING seq
    `
    if (deleted.length > 0) {
      const upto = Math.max(...deleted.map((d) => Number(d.seq)))
      await sql`
        UPDATE sync_circles SET purged_upto = GREATEST(purged_upto, ${upto})
        WHERE user_id = ${userId}
      `
    }
  }
  const oldBlobs = await sql`
    DELETE FROM sync_blobs
    WHERE created_at < NOW() - make_interval(days => ${KEEP_DAYS})
    RETURNING user_id, blob_id, stored_name
  `
  for (const blob of oldBlobs) {
    await removeBlob(blob.stored_name as string)
    await sql`
      DELETE FROM sync_blob_needs WHERE user_id = ${blob.user_id} AND blob_id = ${blob.blob_id}
    `
  }
  await sql`
    DELETE FROM sync_blob_requests WHERE created_at < NOW() - make_interval(days => ${KEEP_DAYS})
  `
  const oldSnapshots = await sql`
    DELETE FROM sync_snapshots
    WHERE created_at < NOW() - make_interval(days => ${SNAPSHOT_KEEP_DAYS})
    RETURNING stored_name
  `
  for (const s of oldSnapshots) await removeBlob(s.stored_name as string)
  await sql`DELETE FROM sync_pairings WHERE expires_at < NOW() - INTERVAL '1 day'`
}
