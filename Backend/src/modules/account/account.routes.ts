import express, { Router } from 'express'
import { requireAuth } from '../../lib/middleware'
import * as controller from './account.controller'

// The app's side, mounted under /api/account.
export const accountRouter = Router()

accountRouter.post('/deletion', requireAuth, controller.requestFromApp)

// The web pages, at the site root. /delete-account is also the address to
// give Google Play ("delete account URL"): it works without the app.
export const deletionPageRouter = Router()

const form = express.urlencoded({ extended: false, limit: '4kb' })
deletionPageRouter.get('/delete-account', controller.page)
deletionPageRouter.post('/delete-account/request', form, controller.requestFromWeb)
deletionPageRouter.post('/delete-account/confirm', form, controller.confirm)
