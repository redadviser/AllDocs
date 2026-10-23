import crypto from 'crypto'
import type { Request, Response } from 'express'
import { pickLang } from '../requests/requests.texts'
import { type DeletionPage, deletionPage } from './account.page'
import * as service from './account.service'

function origin(req: Request): string {
  return `${req.protocol}://${req.get('host')}`
}

function langOf(req: Request) {
  const fromForm = (req.body as Record<string, unknown> | undefined)?.lang
  return pickLang(fromForm ?? req.query.lang ?? req.get('accept-language'))
}

function sendPage(req: Request, res: Response, status: number, page: DeletionPage) {
  const nonce = crypto.randomBytes(16).toString('base64')
  res.set({
    'Content-Type': 'text/html; charset=utf-8',
    // The link's token is in the URL: keep it out of caches and Referers.
    'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer',
    'X-Frame-Options': 'DENY',
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': [
      "default-src 'none'",
      `style-src 'nonce-${nonce}'`,
      "base-uri 'none'",
      "form-action 'self'",
      "frame-ancestors 'none'",
    ].join('; '),
  })
  res.status(status).send(deletionPage(langOf(req), nonce, page))
}

// ---- The app (signed in) ----

/// POST /api/account/deletion: emails the signed-in account its link.
export async function requestFromApp(req: Request, res: Response) {
  try {
    await service.sendDeletionLink(req.user!, pickLang(req.body?.language), origin(req))
    res.json({ sent: true, email: service.maskEmail(req.user!.email) })
  } catch (error) {
    console.error('Account deletion email failed:', error)
    res.status(500).json({ error: 'Could not send the email' })
  }
}

// ---- The web pages (/delete-account) ----

export async function page(req: Request, res: Response) {
  const token = typeof req.query.token === 'string' ? req.query.token : ''
  if (!token) return sendPage(req, res, 200, { kind: 'ask' })
  const account = await service.accountForToken(token).catch(() => null)
  if (!account) return sendPage(req, res, 410, { kind: 'invalid' })
  sendPage(req, res, 200, { kind: 'confirm', token, email: account.email })
}

export async function requestFromWeb(req: Request, res: Response) {
  const email = typeof req.body?.email === 'string' ? req.body.email : ''
  try {
    await service.sendDeletionLinkForEmail(email, langOf(req), origin(req))
  } catch (error) {
    // Logged, not shown: a different answer would reveal the account.
    console.error('Account deletion email (web) failed:', error)
  }
  sendPage(req, res, 200, { kind: 'sent' })
}

export async function confirm(req: Request, res: Response) {
  const token = typeof req.body?.token === 'string' ? req.body.token : ''
  if (req.body?.confirm !== 'yes') {
    const account = await service.accountForToken(token).catch(() => null)
    if (!account) return sendPage(req, res, 410, { kind: 'invalid' })
    return sendPage(req, res, 400, { kind: 'confirm', token, email: account.email })
  }
  try {
    const deleted = await service.deleteWithToken(token)
    sendPage(req, res, deleted ? 200 : 410, { kind: deleted ? 'done' : 'invalid' })
  } catch (error) {
    console.error('Account deletion failed:', error)
    res.status(500).send('Internal server error')
  }
}
