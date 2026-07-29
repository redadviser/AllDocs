import { Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import * as controller from './devices.controller'

export const devicesRouter = Router()

devicesRouter.use(requireAuth)
devicesRouter.get('/', controller.listDevices)
devicesRouter.delete('/:id', controller.revokeDevice)
