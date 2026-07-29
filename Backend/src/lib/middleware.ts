import type { NextFunction, Request, Response } from 'express'
import type { AccountUser } from './auth'
import { getCurrentUser } from './auth'

declare module 'express-serve-static-core' {
  interface Request {
    user?: AccountUser
  }
}

export async function requireAuth(req: Request, res: Response, next: NextFunction) {
  const user = await getCurrentUser(req)
  if (!user) {
    res.status(401).json({ error: 'Not authenticated' })
    return
  }
  req.user = user
  next()
}
