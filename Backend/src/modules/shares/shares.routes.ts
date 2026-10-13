import express, { type NextFunction, type Request, type Response, Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import * as controller from './shares.controller'
import { MAX_SHARE_BYTES } from './shares.service'

// The owner's side, mounted under /api/shares. Creating one sends the file
// as the raw body, with its details in the X-Share-Meta header.
export const sharesRouter = Router()

sharesRouter.use(requireAuth)
sharesRouter.get('/', controller.list)
sharesRouter.post(
  '/',
  express.raw({ type: () => true, limit: MAX_SHARE_BYTES }),
  controller.create
)
sharesRouter.post('/:id/revoke', controller.revoke)
sharesRouter.delete('/:id', controller.remove)

sharesRouter.use(
  (error: { type?: string }, _req: Request, res: Response, next: NextFunction) => {
    if (error?.type === 'entity.too.large') {
      res.status(413).json({ error: 'File too large', code: 'tooBig' })
      return
    }
    next(error)
  }
)

// The link's side, mounted at the site root: the page and the form that
// opens the file (with the access code, when there is one).
export const sharePageRouter = Router()

sharePageRouter.get('/s/:token', controller.page)
sharePageRouter.post(
  '/s/:token/file',
  express.urlencoded({ extended: false, limit: '4kb' }),
  controller.file
)
