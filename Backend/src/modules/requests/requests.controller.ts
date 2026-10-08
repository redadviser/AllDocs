import crypto from 'crypto'
import type { Request, Response } from 'express'
import { requestPage } from './requests.page'
import * as service from './requests.service'
import { pickLang } from './requests.texts'

function origin(req: Request): string {
  return `${req.protocol}://${req.get('host')}`
}

async function handle(res: Response, work: () => Promise<unknown>) {
  try {
    const result = await work()
    res.json(result ?? { success: true })
  } catch (error) {
    if (error instanceof service.RequestError) {
      res.status(error.status).json({ error: error.message, code: error.code })
      return
    }
    console.error('Document request failed:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
}

// ---- The requester (signed in) ----

export function create(req: Request, res: Response) {
  return handle(res, () => service.createRequest(req.user!, req.body ?? {}, origin(req)))
}

export function list(req: Request, res: Response) {
  return handle(res, async () => ({ requests: await service.listRequests(req.user!.id) }))
}

export async function download(req: Request, res: Response) {
  try {
    const file = await service.downloadFile(req.user!.id, req.params.id, req.params.fileId)
    res.set({
      'Content-Type': file.contentType,
      'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(file.name)}`,
      'Cache-Control': 'no-store',
    })
    res.send(file.bytes)
  } catch (error) {
    if (error instanceof service.RequestError) {
      res.status(error.status).json({ error: error.message })
      return
    }
    console.error('Request file download failed:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
}

export function received(req: Request, res: Response) {
  return handle(res, () => service.markReceived(req.user!.id, req.params.id, req.params.fileId))
}

export function close(req: Request, res: Response) {
  return handle(res, () => service.closeRequest(req.user!.id, req.params.id))
}

export function remove(req: Request, res: Response) {
  return handle(res, () => service.deleteRequest(req.user!.id, req.params.id))
}

// ---- The person asked (public, by link) ----

export async function page(req: Request, res: Response) {
  const token = req.params.token
  let request: Awaited<ReturnType<typeof service.openRequestByToken>> = null
  try {
    request = await service.openRequestByToken(token)
  } catch (error) {
    console.error('openRequestByToken failed:', error)
  }
  const lang = request?.language ?? pickLang(req.get('accept-language'))
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
      "base-uri 'none'",
      "form-action 'none'",
      "frame-ancestors 'none'",
    ].join('; '),
  })
  res.status(request ? 200 : 404).send(requestPage({ lang, token, nonce, request }))
}

export function upload(req: Request, res: Response) {
  return handle(res, () =>
    service.receiveUpload(req.params.token, req.query.name, req.get('content-type'), req.body)
  )
}
