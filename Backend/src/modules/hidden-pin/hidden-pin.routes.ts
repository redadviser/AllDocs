import { Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import * as controller from './hidden-pin.controller'

// The account's side, mounted under /api/security/hidden-pin-reset.
export const hiddenPinRouter = Router()

hiddenPinRouter.use(requireAuth)
hiddenPinRouter.get('/', controller.status)
hiddenPinRouter.post('/request', controller.request)
hiddenPinRouter.post('/verify', controller.verify)
hiddenPinRouter.post('/complete', controller.complete)
hiddenPinRouter.post('/cancel', controller.cancel)

// The warning email's cancel link (no session needed: the token is it).
export const hiddenPinPageRouter = Router()

hiddenPinPageRouter.get('/hidden-pin/cancel', controller.cancelPage)
