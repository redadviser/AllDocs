import { Router } from 'express'
import * as controller from './auth.controller'

export const authRouter = Router()

authRouter.post('/login', controller.login)
authRouter.post('/signup', controller.signup)
authRouter.post('/google/signin', controller.googleSignIn)
authRouter.post('/logout', controller.logout)
authRouter.get('/me', controller.me)
