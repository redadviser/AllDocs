import type { Request, Response } from 'express'
import { isEscrowConfigured } from '../../lib/key-escrow'
import * as service from './vault-key.service'

// Answers carry a key: never cached, and the body never logged.
async function handle(res: Response, work: () => Promise<void>) {
  res.set('Cache-Control', 'no-store')
  if (!isEscrowConfigured()) {
    res.status(503).json({ error: 'Key backup is not available', code: 'unavailable' })
    return
  }
  try {
    await work()
  } catch (error) {
    if (error instanceof service.VaultKeyError) {
      res.status(error.status).json({ error: error.message, code: error.code })
      return
    }
    console.error('Vault key failed:', error instanceof Error ? error.message : 'unknown error')
    res.status(500).json({ error: 'Internal server error' })
  }
}

export function get(req: Request, res: Response) {
  return handle(res, async () => {
    const stored = await service.getKey(req.user!.id)
    if (!stored) {
      res.status(404).json({ error: 'No key stored', code: 'notFound' })
      return
    }
    res.json(stored)
  })
}

export function put(req: Request, res: Response) {
  return handle(res, async () => {
    const result = await service.putKey(req.user!.id, req.body ?? {})
    res.status(result === 'created' ? 201 : 200).json({ success: true })
  })
}
