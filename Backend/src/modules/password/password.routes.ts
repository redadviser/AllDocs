import { Router } from 'express'
import { codeLimiter, emailLimiter } from '../../lib/rate-limit'
import * as controller from './password.controller'

// API side of "forgot password", mounted under /api/auth/password.
export const passwordRouter = Router()

passwordRouter.post('/forgot', emailLimiter, controller.forgotPassword)
passwordRouter.post('/reset', codeLimiter, controller.resetPasswordHandler)

// The HTML page the reset email links to, mounted at the site root.
export const resetPageRouter = Router()

resetPageRouter.get('/reset-password', codeLimiter, controller.resetPasswordPageHandler)
