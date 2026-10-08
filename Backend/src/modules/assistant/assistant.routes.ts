import { Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import * as controller from './assistant.controller'

export const assistantRouter = Router()

assistantRouter.use(requireAuth)
assistantRouter.get('/usage', controller.usage)
assistantRouter.post('/ask', controller.ask)
assistantRouter.post('/extract', controller.extract)
assistantRouter.post('/summarize', controller.summarize)
