import { Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import * as controller from './plans.controller'

export const plansRouter = Router()

plansRouter.use(requireAuth)
plansRouter.get('/', controller.getPlans)
plansRouter.post('/sync', controller.syncPlan)

// Called by Adapty, authenticated by its Authorization header instead of a
// session.
export const adaptyWebhookRouter = Router()

adaptyWebhookRouter.post('/webhook', controller.adaptyWebhook)
