import type { Request, Response } from 'express'
import {
  clearSessionCookieConfig,
  getCurrentUser,
  sessionCookieConfig,
} from '../../lib/auth'
import * as authService from './auth.service'

export async function login(req: Request, res: Response) {
  try {
    const { email, password, device } = req.body
    if (!email || !password) {
      res.status(400).json({ error: 'Email and password are required' })
      return
    }

    const { user, token } = await authService.login(email, password, device)
    const cookie = sessionCookieConfig(token)
    res.cookie(cookie.name, cookie.value, cookie.options)
    res.json({ user })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Login failed'
    res.status(401).json({ error: message })
  }
}

export async function signup(req: Request, res: Response) {
  try {
    const { email, password, device } = req.body
    if (!email || !password) {
      res.status(400).json({ error: 'Email and password are required' })
      return
    }
    if (password.length < 6) {
      res.status(400).json({ error: 'Password must be at least 6 characters' })
      return
    }

    const { user, token } = await authService.signup(email, password, device)
    const cookie = sessionCookieConfig(token)
    res.cookie(cookie.name, cookie.value, cookie.options)
    res.json({ user })
  } catch (error) {
    res.status(400).json({ error: error instanceof Error ? error.message : 'Sign up failed' })
  }
}

export async function logout(_req: Request, res: Response) {
  const cookie = clearSessionCookieConfig()
  res.clearCookie(cookie.name, cookie.options)
  res.json({ success: true })
}

export async function me(req: Request, res: Response) {
  const user = await getCurrentUser(req)
  if (!user) {
    res.status(401).json({ user: null })
    return
  }
  res.json({ user })
}
