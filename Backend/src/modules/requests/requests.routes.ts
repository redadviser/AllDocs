import express, { type NextFunction, type Request, type Response, Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import * as controller from './requests.controller'
import { MAX_FILE_BYTES } from './requests.service'

// The requester's side, mounted under /api/requests.
export const requestsRouter = Router()

requestsRouter.use(requireAuth)
requestsRouter.get('/', controller.list)
requestsRouter.post('/', controller.create)
requestsRouter.post('/:id/close', controller.close)
requestsRouter.delete('/:id', controller.remove)
requestsRouter.get('/:id/files/:fileId', controller.download)
requestsRouter.post('/:id/files/:fileId/received', controller.received)

// The link's side, mounted at the site root: the page and its uploads (the
// file is the raw request body, one per request).
export const requestPageRouter = Router()

requestPageRouter.get('/r/:token', controller.page)
requestPageRouter.post(
  '/r/:token/files',
  express.raw({ type: () => true, limit: MAX_FILE_BYTES }),
  controller.upload
)

// A file over the limit is refused by the body parser before the handler
// runs; answer it like the page expects.
requestPageRouter.use(
  (error: { type?: string }, _req: Request, res: Response, next: NextFunction) => {
    if (error?.type === 'entity.too.large') {
      res.status(413).json({ error: 'File too large', code: 'tooBig' })
      return
    }
    next(error)
  }
)
