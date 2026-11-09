import { Router } from 'express'
import { loginLimiter, signupLimiter } from '../../lib/rate-limit'
import * as controller from './auth.controller'

export const authRouter = Router()

authRouter.post('/login', loginLimiter, controller.login)
authRouter.post('/signup', signupLimiter, controller.signup)
authRouter.post('/google/signin', signupLimiter, controller.googleSignIn)
authRouter.post('/logout', controller.logout)
authRouter.get('/me', controller.me)
