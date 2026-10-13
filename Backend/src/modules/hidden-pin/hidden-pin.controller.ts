import type { Request, Response } from 'express'
import { pickLang } from '../requests/requests.texts'
import * as service from './hidden-pin.service'

function origin(req: Request): string {
  return `${req.protocol}://${req.get('host')}`
}

async function handle(res: Response, work: () => Promise<unknown>) {
  try {
    res.json((await work()) ?? { success: true })
  } catch (error) {
    if (error instanceof service.HiddenPinResetError) {
      res.status(error.status).json({
        error: error.message,
        code: error.code,
        attemptsLeft: error.attemptsLeft,
      })
      return
    }
    console.error('Hidden PIN reset failed:', error)
    res.status(500).json({ error: 'Internal server error' })
  }
}

export function status(req: Request, res: Response) {
  return handle(res, () => service.status(req.user!.id))
}

export function request(req: Request, res: Response) {
  return handle(res, () => service.requestCode(req.user!, req.body?.language))
}

export function verify(req: Request, res: Response) {
  return handle(res, () =>
    service.verifyCode(req.user!, req.body?.code, req.body?.language, origin(req))
  )
}

export function complete(req: Request, res: Response) {
  return handle(res, () => service.complete(req.user!.id))
}

export function cancel(req: Request, res: Response) {
  return handle(res, () => service.cancel(req.user!.id))
}

export async function cancelPage(req: Request, res: Response) {
  const lang = pickLang(req.query.lang ?? req.get('accept-language'))
  let cancelled = false
  try {
    cancelled = await service.cancelByToken(String(req.query.token ?? ''))
  } catch (error) {
    console.error('Hidden PIN reset cancel failed:', error)
  }
  res.set({
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer',
    'X-Frame-Options': 'DENY',
    'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'",
  })
  res.status(cancelled ? 200 : 404).send(service.cancelPage(lang, cancelled))
}
