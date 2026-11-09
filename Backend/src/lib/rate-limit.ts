import type { Request } from 'express'
import { rateLimit, ipKeyGenerator, type Options } from 'express-rate-limit'

// Request limits per client IP (req.ip: the address CapRover's nginx saw,
// see `trust proxy` in main.ts). Counts live in memory, which is right for
// the single backend instance; they reset on a restart.
//
// Phones on mobile data often share one public IP, so the limits on the
// whole API are generous; the tight ones guard what is worth guessing
// (passwords, codes) or costs something per call (emails sent).

const MINUTE = 60 * 1000

function limiter(options: Partial<Options>) {
  return rateLimit({
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    message: { error: 'Too many requests, try again later', code: 'rateLimited' },
    ...options,
  })
}

function ip(req: Request): string {
  return ipKeyGenerator(req.ip ?? '')
}

function emailOf(req: Request): string {
  const email = req.body?.email
  return typeof email === 'string' ? email.trim().toLowerCase() : ''
}

/// Everything under /api, as a backstop against floods.
export const apiLimiter = limiter({
  windowMs: MINUTE,
  limit: 600,
  // Adapty retries on its own schedule; its requests are authenticated.
  skip: (req) => req.path === '/adapty/webhook',
})

/// Signing in: failed attempts per IP and email, so one address can't be
/// guessed at, plus a cap per IP across all emails.
export const loginLimiter = [
  limiter({
    windowMs: 15 * MINUTE,
    limit: 10,
    skipSuccessfulRequests: true,
    keyGenerator: (req) => `${ip(req)}|${emailOf(req)}`,
  }),
  limiter({ windowMs: 15 * MINUTE, limit: 100, skipSuccessfulRequests: true }),
]

/// New accounts per IP.
export const signupLimiter = limiter({ windowMs: 60 * MINUTE, limit: 20 })

/// Requests that send an email (password reset, account deletion, hidden
/// PIN reset): a few per hour, so nobody's inbox can be flooded through us.
export const emailLimiter = [
  limiter({
    windowMs: 60 * MINUTE,
    limit: 5,
    keyGenerator: (req) => `${ip(req)}|${emailOf(req) || req.user?.id || ''}`,
  }),
  limiter({ windowMs: 60 * MINUTE, limit: 30 }),
]

/// Codes and one-time tokens typed or pasted in (reset tokens, deletion
/// confirmation, hidden PIN code, share access code). Each has its own
/// attempt limit too; this stops trying many of them from one place.
export const codeLimiter = limiter({ windowMs: 15 * MINUTE, limit: 30 })

/// The public link pages (/r/, /s/) and the files uploaded through them.
export const publicPageLimiter = limiter({ windowMs: MINUTE, limit: 60 })
export const publicUploadLimiter = limiter({ windowMs: 10 * MINUTE, limit: 60 })

/// The document assistant, on top of its monthly quota: no bursts.
export const assistantLimiter = limiter({
  windowMs: MINUTE,
  limit: 20,
  keyGenerator: (req) => req.user?.id ?? ip(req),
})
