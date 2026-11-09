import { Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import { codeLimiter, emailLimiter } from '../../lib/rate-limit'
import * as controller from './hidden-pin.controller'

// The account's side, mounted under /api/security/hidden-pin-reset.
export const hiddenPinRouter = Router()

hiddenPinRouter.use(requireAuth)
hiddenPinRouter.get('/', controller.status)
hiddenPinRouter.post('/request', emailLimiter, controller.request)
hiddenPinRouter.post('/verify', codeLimiter, controller.verify)
hiddenPinRouter.post('/complete', controller.complete)
hiddenPinRouter.post('/cancel', controller.cancel)

// The warning email's cancel link (no session needed: the token is it).
export const hiddenPinPageRouter = Router()

hiddenPinPageRouter.get('/hidden-pin/cancel', codeLimiter, controller.cancelPage)
