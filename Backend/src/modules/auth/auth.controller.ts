import type { Request, Response } from 'express'
import {
  clearSessionCookieConfig,
  getCurrentUser,
  sessionCookieConfig,
  sessionEndReason,
  sessionToken,
} from '../../lib/auth'
import { sql } from '../../lib/db'
import { releaseSessionDevices } from '../sync/sync.service'
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
    const { email, password, displayName, device } = req.body
    if (!email || !password) {
      res.status(400).json({ error: 'Email and password are required' })
      return
    }
    if (password.length < 6) {
      res.status(400).json({ error: 'Password must be at least 6 characters' })
      return
    }

    const { user, token } = await authService.signup(email, password, displayName, device)
    const cookie = sessionCookieConfig(token)
    res.cookie(cookie.name, cookie.value, cookie.options)
    res.json({ user })
  } catch (error) {
    res.status(400).json({ error: error instanceof Error ? error.message : 'Sign up failed' })
  }
}

export async function googleSignIn(req: Request, res: Response) {
  try {
    const { idToken, device } = req.body
    if (!idToken) {
      res.status(400).json({ error: 'idToken is required' })
      return
    }

    const { user, token } = await authService.loginWithGoogle(idToken, device)
    const cookie = sessionCookieConfig(token)
    res.cookie(cookie.name, cookie.value, cookie.options)
    res.json({ user })
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Google sign-in failed'
    res.status(401).json({ error: message })
  }
}

export async function logout(req: Request, res: Response) {
  // Signing out ends this phone's session for good: off the devices list,
  // and out of sync (its place is free for another phone).
  const user = await getCurrentUser(req)
  if (user?.deviceId) {
    try {
      await sql`DELETE FROM devices WHERE id = ${user.deviceId} AND user_id = ${user.id}`
      await releaseSessionDevices(user.id, [user.deviceId])
    } catch (error) {
      console.error('Sign-out cleanup failed:', error)
    }
  }
  const cookie = clearSessionCookieConfig()
  res.clearCookie(cookie.name, cookie.options)
  res.json({ success: true })
}

export async function me(req: Request, res: Response) {
  const user = await getCurrentUser(req)
  if (!user) {
    // The app tells "your account was deleted" from "signed out elsewhere".
    res.status(401).json({ user: null, code: await sessionEndReason(sessionToken(req)) })
    return
  }
  res.json({ user })
}
