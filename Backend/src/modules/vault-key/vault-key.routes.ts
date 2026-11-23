import { Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import { vaultKeyLimiter } from '../../lib/rate-limit'
import * as controller from './vault-key.controller'

// The copy of the account's library key, mounted under
// /api/security/vault-key. No DELETE: deleting the account removes it.
export const vaultKeyRouter = Router()
vaultKeyRouter.use(requireAuth, vaultKeyLimiter)
vaultKeyRouter.get('/', controller.get)
vaultKeyRouter.put('/', controller.put)
