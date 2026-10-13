import crypto from 'crypto'
import type { Request, Response } from 'express'
import { pickLang } from '../requests/requests.texts'
import { sharePage } from './shares.page'
import * as service from './shares.service'

function origin(req: Request): string {
  return `${req.protocol}://${req.get('host')}`
}

async function handle(res: Response, work: () => Promise<unknown>) {
  try {
    const result = await work()
    res.json(result ?? { success: true })
  } catch (error) {
    if (error instanceof service.ShareError) {
      res.status(error.status).json({ error: error.message, code: error.code })
      return
    }
    console.error('Secure share failed:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
}

// The X-Share-Meta header: base64url JSON (title, fileName, days, code,
// maxViews, language) — the body is the file itself.
function shareMeta(req: Request): Record<string, unknown> {
  try {
    const raw = Buffer.from(req.get('x-share-meta') ?? '', 'base64url').toString('utf8')
    const parsed = JSON.parse(raw)
    return parsed && typeof parsed === 'object' ? parsed : {}
  } catch {
    return {}
  }
}

// ---- The owner (signed in) ----

export function create(req: Request, res: Response) {
  return handle(res, () => service.createShare(req.user!, shareMeta(req), req.body, origin(req)))
}

export function list(req: Request, res: Response) {
  return handle(res, async () => ({ shares: await service.listShares(req.user!.id) }))
}

export function revoke(req: Request, res: Response) {
  return handle(res, () => service.revokeShare(req.user!.id, req.params.id))
}

export function remove(req: Request, res: Response) {
  return handle(res, () => service.deleteShare(req.user!.id, req.params.id))
}

// ---- Whoever has the link (public) ----

function sendPage(
  req: Request,
  res: Response,
  status: number,
  share: service.OpenShare | null,
  error: 'wrongCode' | null = null
) {
  const lang = share?.language ?? pickLang(req.get('accept-language'))
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
      `style-src 'nonce-${nonce}'`,
      "base-uri 'none'",
      "form-action 'self'",
      "frame-ancestors 'none'",
    ].join('; '),
  })
  res.status(status).send(sharePage({ lang, token: req.params.token, nonce, share, error }))
}

export async function page(req: Request, res: Response) {
  let share: service.OpenShare | null = null
  try {
    share = await service.findShareByToken(req.params.token)
  } catch (error) {
    console.error('findShareByToken failed:', error)
  }
  sendPage(req, res, share?.status === 'active' ? 200 : 404, share)
}

export async function file(req: Request, res: Response) {
  const token = req.params.token
  const body = (req.body ?? {}) as Record<string, unknown>
  try {
    const opened = await service.openShareFile(token, body.code, body.mode === 'download')
    const disposition = opened.inline ? 'inline' : 'attachment'
    res.set({
      'Content-Type': opened.contentType,
      'Content-Disposition': `${disposition}; filename*=UTF-8''${encodeURIComponent(opened.fileName)}`,
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
      'X-Content-Type-Options': 'nosniff',
      // Shown as a document, never run as a page.
      'Content-Security-Policy': "sandbox; default-src 'none'; img-src 'self'; style-src 'unsafe-inline'",
    })
    res.send(opened.bytes)
  } catch (error) {
    if (error instanceof service.ShareError) {
      const share = await service.findShareByToken(token).catch(() => null)
      if (error.code === 'wrongCode') return sendPage(req, res, 403, share, 'wrongCode')
      return sendPage(req, res, error.code === 'locked' ? 403 : 404, share)
    }
    console.error('Secure share file failed:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
}
