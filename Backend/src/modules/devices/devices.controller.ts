import type { Request, Response } from 'express'
import { sql } from '../../lib/db'

export async function listDevices(req: Request, res: Response) {
  const userId = req.user!.id

  const rows = await sql`
    SELECT id, platform, name, last_seen_at, created_at
    FROM devices
    WHERE user_id = ${userId}
    ORDER BY last_seen_at DESC
  `

  res.json({
    devices: rows.map((row) => ({
      id: row.id as string,
      platform: row.platform as string,
      name: (row.name as string | null) ?? null,
      lastSeenAt: row.last_seen_at as Date,
      createdAt: row.created_at as Date,
    })),
  })
}

// Deleting the row is the whole mechanism: getCurrentUserFromToken checks
// a token's deviceId claim against this table on every request, so this
// ends that device's session immediately, not just removes a list entry.
export async function revokeDevice(req: Request, res: Response) {
  const userId = req.user!.id
  const { id } = req.params

  const result = await sql`
    DELETE FROM devices WHERE id = ${id} AND user_id = ${userId}
  `
  if (result.count === 0) {
    res.status(404).json({ error: 'Device not found' })
    return
  }

  res.json({ success: true })
}

export async function revokeAllDevices(req: Request, res: Response) {
  const userId = req.user!.id
  await sql`DELETE FROM devices WHERE user_id = ${userId}`
  res.json({ success: true })
}
