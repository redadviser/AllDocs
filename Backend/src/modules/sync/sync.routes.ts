import express, { type NextFunction, type Request, type Response, Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import * as controller from './sync.controller'
import { MAX_CHANGE_BYTES } from './sync.service'

// Device sync, mounted under /api/sync. Calls made as a device carry its id
// in X-Sync-Device. Blobs and snapshots are the raw (already encrypted)
// body, streamed to disk; a change batch is the raw body too.
export const syncRouter = Router()

syncRouter.use(requireAuth)
syncRouter.get('/', controller.status)
syncRouter.post('/devices', controller.register)
syncRouter.delete('/devices/:id', controller.removeDevice)
syncRouter.post('/pairings', controller.createPairing)
syncRouter.post('/pairings/status', controller.pairingStatus)
syncRouter.get('/changes', controller.pull)
syncRouter.post(
  '/changes',
  express.raw({ type: () => true, limit: MAX_CHANGE_BYTES }),
  controller.push
)
syncRouter.post('/blobs/existing', controller.existingBlobs)
syncRouter.post('/blobs/requests', controller.requestBlobs)
syncRouter.put('/blobs/:blobId', controller.putBlob)
syncRouter.get('/blobs/:blobId', controller.getBlob)
syncRouter.post('/blobs/:blobId/ack', controller.ackBlob)
syncRouter.put('/snapshots/:deviceId', controller.putSnapshot)
syncRouter.get('/snapshot', controller.getSnapshot)
syncRouter.post('/snapshot/ack', controller.ackSnapshot)

syncRouter.use(
  (error: { type?: string }, _req: Request, res: Response, next: NextFunction) => {
    if (error?.type === 'entity.too.large') {
      res.status(413).json({ error: 'Batch too large', code: 'tooBig' })
      return
    }
    next(error)
  }
)
