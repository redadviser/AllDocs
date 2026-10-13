import type { Request, Response } from 'express'
import { waitForNews } from './sync.events'
import * as service from './sync.service'

async function handle(res: Response, work: () => Promise<unknown>) {
  try {
    const result = await work()
    res.json(result ?? { success: true })
  } catch (error) {
    fail(res, error)
  }
}

function fail(res: Response, error: unknown) {
  if (res.headersSent) {
    res.destroy()
    return
  }
  if (error instanceof service.SyncError) {
    res.status(error.status).json({ error: error.message, code: error.code })
    return
  }
  console.error('Sync failed:', error)
  res.status(500).json({ error: 'Internal server error' })
}

/// The calling device, from the X-Sync-Device header (Vault only).
async function device(req: Request) {
  service.requireSync(req.user!)
  return service.deviceFor(req.user!, req.get('x-sync-device'))
}

export function status(req: Request, res: Response) {
  return handle(res, () => service.status(req.user!))
}

export function register(req: Request, res: Response) {
  return handle(res, () => service.registerDevice(req.user!, req.body ?? {}))
}

export function removeDevice(req: Request, res: Response) {
  return handle(res, () => service.removeDevice(req.user!, req.params.id))
}

export function createPairing(req: Request, res: Response) {
  return handle(res, async () => service.createPairing(req.user!, (await device(req)).id))
}

export function pairingStatus(req: Request, res: Response) {
  return handle(res, async () => {
    service.requireSync(req.user!)
    return service.pairingStatus(req.user!, req.body?.code)
  })
}

// How long a wait hangs before answering "nothing new" (under the proxies'
// usual 60 s read timeout).
const WAIT_MS = 25_000

/// Long poll: answers {changed: true} as soon as there's something for this
/// device to do, or {changed: false} after WAIT_MS.
export function wait(req: Request, res: Response) {
  return handle(res, async () => {
    const caller = await device(req)
    const after = Math.max(0, Number(req.query.after) || 0)
    // A device waiting for the library only wakes when it arrives.
    if (!caller.needsSnapshot && (await service.hasChangesAfter(req.user!, caller.id, after))) {
      return { changed: true }
    }
    const changed = await waitForNews(req.user!.id, caller.id, WAIT_MS, (cancel) =>
      req.on('close', cancel)
    )
    return { changed }
  })
}

export function pull(req: Request, res: Response) {
  return handle(res, async () =>
    service.pull(req.user!, await device(req), Math.max(0, Number(req.query.after) || 0))
  )
}

export function push(req: Request, res: Response) {
  return handle(res, async () =>
    service.push(req.user!, (await device(req)).id, Number(req.query.base) || 0, req.body)
  )
}

export function existingBlobs(req: Request, res: Response) {
  return handle(res, async () => {
    await device(req)
    return service.existingBlobs(req.user!, req.body?.ids)
  })
}

export function requestBlobs(req: Request, res: Response) {
  return handle(res, async () =>
    service.requestBlobs(req.user!, (await device(req)).id, req.body?.ids)
  )
}

export async function putBlob(req: Request, res: Response) {
  return handle(res, async () =>
    service.putBlob(
      req.user!,
      (await device(req)).id,
      req.params.blobId,
      req.query.for === 'all',
      Number(req.get('content-length')) || 0,
      req
    )
  )
}

export async function getBlob(req: Request, res: Response) {
  try {
    await device(req)
    const blob = await service.getBlob(req.user!, req.params.blobId)
    res.set({
      'Content-Type': 'application/octet-stream',
      'Content-Length': String(blob.size),
      'Cache-Control': 'no-store',
    })
    blob.stream.on('error', (error) => fail(res, error))
    blob.stream.pipe(res)
  } catch (error) {
    fail(res, error)
  }
}

export function ackBlob(req: Request, res: Response) {
  return handle(res, async () =>
    service.ackBlob(req.user!, (await device(req)).id, req.params.blobId)
  )
}

export function putSnapshot(req: Request, res: Response) {
  return handle(res, async () => {
    await device(req)
    return service.putSnapshot(
      req.user!,
      req.params.deviceId,
      Math.max(0, Number(req.query.upto) || 0),
      req
    )
  })
}

export async function getSnapshot(req: Request, res: Response) {
  try {
    const snapshot = await service.getSnapshot((await device(req)).id)
    res.set({
      'Content-Type': 'application/octet-stream',
      'Content-Length': String(snapshot.size),
      'X-Upto-Seq': String(snapshot.uptoSeq),
      'Cache-Control': 'no-store',
    })
    snapshot.stream.on('error', (error) => fail(res, error))
    snapshot.stream.pipe(res)
  } catch (error) {
    fail(res, error)
  }
}

export function ackSnapshot(req: Request, res: Response) {
  return handle(res, async () => service.ackSnapshot((await device(req)).id))
}
