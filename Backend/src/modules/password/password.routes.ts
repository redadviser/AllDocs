import { Router } from 'express'
import * as controller from './password.controller'

// API side of "forgot password", mounted under /api/auth/password.
export const passwordRouter = Router()

passwordRouter.post('/forgot', controller.forgotPassword)
passwordRouter.post('/reset', controller.resetPasswordHandler)

// The HTML page the reset email links to, mounted at the site root.
export const resetPageRouter = Router()

resetPageRouter.get('/reset-password', controller.resetPasswordPageHandler)
