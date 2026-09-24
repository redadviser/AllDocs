import crypto from 'crypto'
import type { Request, Response } from 'express'
import { resetPasswordPage } from './password.page'
import {
  InvalidResetTokenError,
  isResetTokenValid,
  MIN_PASSWORD_LENGTH,
  requestPasswordReset,
  resetPassword,
} from './password.service'
import { langFromHeader, pickLang } from './password.texts'

// POST /api/auth/password/forgot — always the same answer, whether or not
// the email has an account.
export async function forgotPassword(req: Request, res: Response) {
  const { email, lang } = req.body ?? {}
  if (typeof email !== 'string' || !email.trim()) {
    res.status(400).json({ error: 'email is required' })
    return
  }
  try {
    await requestPasswordReset(email, pickLang(lang), `${req.protocol}://${req.get('host')}`)
  } catch (error) {
    // Logged, not surfaced: a different answer would reveal the account.
    console.error('requestPasswordReset failed:', error)
  }
  res.json({ success: true })
}

// POST /api/auth/password/reset — used by the reset page's form.
export async function resetPasswordHandler(req: Request, res: Response) {
  const { token, password } = req.body ?? {}
  if (typeof token !== 'string' || typeof password !== 'string') {
    res.status(400).json({ error: 'token and password are required' })
    return
  }
  if (password.length < MIN_PASSWORD_LENGTH) {
    res.status(400).json({ error: `Password must be at least ${MIN_PASSWORD_LENGTH} characters` })
    return
  }
  try {
    await resetPassword(token, password)
    res.json({ success: true })
  } catch (error) {
    if (error instanceof InvalidResetTokenError) {
      res.status(400).json({ error: 'Invalid or expired link' })
      return
    }
    console.error('resetPassword failed:', error)
    res.status(500).json({ error: 'Could not reset the password' })
  }
}

// GET /reset-password?token=...&lang=... — the page the email links to.
export async function resetPasswordPageHandler(req: Request, res: Response) {
  const token = typeof req.query.token === 'string' ? req.query.token : ''
  const lang = req.query.lang
    ? pickLang(req.query.lang)
    : langFromHeader(req.get('accept-language'))
  let valid = false
  try {
    valid = await isResetTokenValid(token)
  } catch (error) {
    // Shown as "invalid or expired"; asking for a new link is the way out.
    console.error('isResetTokenValid failed:', error)
  }
  const nonce = crypto.randomBytes(16).toString('base64')

  res.set({
    'Content-Type': 'text/html; charset=utf-8',
    // The token is in the URL: keep it out of caches and Referer headers.
    'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer',
    'X-Frame-Options': 'DENY',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': [
      "default-src 'none'",
      `script-src 'nonce-${nonce}'`,
      `style-src 'nonce-${nonce}'`,
      "connect-src 'self'",
      "form-action 'self'",
      "base-uri 'none'",
      "frame-ancestors 'none'",
    ].join('; '),
  })
  res.send(resetPasswordPage({ lang, token, valid, nonce }))
}
