import crypto from 'crypto'
import { sql } from '../../lib/db'
import { sendMail } from '../../lib/mailer'
import { escapeHtml, publicBaseUrl } from '../password/password.service'
import { type Lang, pickLang } from '../requests/requests.texts'
import { texts } from './hidden-pin.texts'

// Resetting the hidden albums' PIN. That PIN lives on the phone, so the
// server only decides when the app may set a new one: after a code sent to
// the account's email is confirmed, and then a wait — so someone holding an
// unlocked phone (with the account's email open on it) can't do it on the
// spot, and the owner gets a warning email that cancels it.

const CODE_MINUTES = 15
const MAX_ATTEMPTS = 5
const MAX_REQUESTS_PER_DAY = 5

// 24 h; shorter only on a development server, for testing.
function waitHours(): number {
  const configured = Number(process.env.HIDDEN_PIN_RESET_WAIT_HOURS)
  if (process.env.NODE_ENV !== 'production' && configured >= 0 && process.env.HIDDEN_PIN_RESET_WAIT_HOURS) {
    return configured
  }
  return 24
}

export class HiddenPinResetError extends Error {
  constructor(
    readonly status: number,
    message: string,
    readonly code: string,
    readonly attemptsLeft?: number
  ) {
    super(message)
  }
}

type User = { id: string; email: string }

function hash(value: string): string {
  return crypto.createHash('sha256').update(value).digest('hex')
}

async function activeReset(userId: string) {
  const rows = await sql`
    SELECT * FROM hidden_pin_resets
    WHERE user_id = ${userId} AND cancelled_at IS NULL AND completed_at IS NULL
    ORDER BY created_at DESC
    LIMIT 1
  `
  return rows[0] ?? null
}

/// Where the account's reset is: none, a code waiting to be confirmed, the
/// wait, or ready to set the new PIN. [cancelled]: the last one was
/// cancelled in the past day (from the warning email, most likely).
export async function status(userId: string) {
  const row = await activeReset(userId)
  const recentCancel = await sql`
    SELECT 1 FROM hidden_pin_resets
    WHERE user_id = ${userId} AND verified_at IS NOT NULL
      AND cancelled_at > NOW() - INTERVAL '1 day'
    LIMIT 1
  `
  const cancelled = recentCancel.length > 0
  if (!row) return { state: 'none' as const, cancelled }
  if (!row.verified_at) {
    const expired = (row.code_expires_at as Date).getTime() <= Date.now()
    if (expired || Number(row.attempts) >= MAX_ATTEMPTS) return { state: 'none' as const, cancelled }
    return {
      state: 'codeSent' as const,
      codeExpiresAt: row.code_expires_at as Date,
      attemptsLeft: MAX_ATTEMPTS - Number(row.attempts),
      cancelled,
    }
  }
  const readyAt = row.ready_at as Date
  return {
    state: readyAt.getTime() <= Date.now() ? ('ready' as const) : ('waiting' as const),
    readyAt,
    cancelled,
  }
}

/// Sends a code to the account's email (unless a reset is already past
/// that step).
export async function requestCode(user: User, language: unknown) {
  const lang = pickLang(language)
  const current = await activeReset(user.id)
  if (current?.verified_at) return status(user.id)

  const recent = await sql`
    SELECT COUNT(*)::int AS n FROM hidden_pin_resets
    WHERE user_id = ${user.id} AND created_at > NOW() - INTERVAL '1 day'
  `
  if (Number(recent[0].n) >= MAX_REQUESTS_PER_DAY) {
    throw new HiddenPinResetError(429, 'Too many codes today', 'tooManyRequests')
  }
  // A new code replaces one not confirmed yet (which simply expires).
  await sql`
    UPDATE hidden_pin_resets SET code_expires_at = NOW()
    WHERE user_id = ${user.id} AND verified_at IS NULL AND cancelled_at IS NULL
      AND completed_at IS NULL
  `
  const id = crypto.randomUUID()
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0')
  await sql`
    INSERT INTO hidden_pin_resets (id, user_id, code_hash, code_expires_at)
    VALUES (
      ${id}, ${user.id}, ${hash(`${id}:${code}`)},
      NOW() + (${CODE_MINUTES} * INTERVAL '1 minute')
    )
  `
  const t = texts[lang]
  const note = t.codeNote
    .replace('{minutes}', String(CODE_MINUTES))
    .replace('{hours}', String(waitHours()))
  await sendMail({
    to: user.email,
    subject: t.codeSubject,
    text: `${t.codeBody}\n\n${code}\n\n${note}`,
    html: emailHtml(lang, [
      { text: t.codeBody },
      { code },
      { text: note, muted: true },
    ]),
  })
  return status(user.id)
}

/// Checks the code; when right, the wait starts and the warning email (with
/// its cancel link) goes out.
export async function verifyCode(user: User, rawCode: unknown, language: unknown, origin: string) {
  const lang = pickLang(language)
  const row = await activeReset(user.id)
  if (!row || row.verified_at) {
    throw new HiddenPinResetError(409, 'No code waiting to be confirmed', 'noCode')
  }
  if ((row.code_expires_at as Date).getTime() <= Date.now()) {
    throw new HiddenPinResetError(410, 'The code expired', 'expired')
  }
  if (Number(row.attempts) >= MAX_ATTEMPTS) {
    throw new HiddenPinResetError(429, 'Too many wrong codes', 'tooManyAttempts')
  }
  const code = String(rawCode ?? '').replace(/\D/g, '')
  const expected = Buffer.from(row.code_hash as string, 'hex')
  const given = Buffer.from(hash(`${row.id}:${code}`), 'hex')
  if (code.length !== 6 || !crypto.timingSafeEqual(expected, given)) {
    const updated = await sql`
      UPDATE hidden_pin_resets SET attempts = attempts + 1
      WHERE id = ${row.id} RETURNING attempts
    `
    const left = MAX_ATTEMPTS - Number(updated[0].attempts)
    throw new HiddenPinResetError(
      left > 0 ? 400 : 429,
      'Wrong code',
      left > 0 ? 'wrongCode' : 'tooManyAttempts',
      left
    )
  }

  const cancelToken = crypto.randomBytes(24).toString('base64url')
  await sql`
    UPDATE hidden_pin_resets
    SET verified_at = NOW(),
        ready_at = NOW() + (${waitHours()} * INTERVAL '1 hour'),
        cancel_token_hash = ${hash(cancelToken)}
    WHERE id = ${row.id}
  `
  const t = texts[lang]
  const link = `${publicBaseUrl(origin)}/hidden-pin/cancel?token=${cancelToken}&lang=${lang}`
  const body = t.warnBody.replace('{hours}', String(waitHours()))
  await sendMail({
    to: user.email,
    subject: t.warnSubject,
    text: `${body}\n\n${link}\n\n${t.warnAdvice}`,
    html: emailHtml(lang, [
      { text: body },
      { button: t.warnButton, href: link },
      { text: t.warnAdvice, muted: true },
    ]),
  })
  return status(user.id)
}

/// The wait is over: the app may set the new PIN now. Single use.
export async function complete(userId: string) {
  const rows = await sql`
    UPDATE hidden_pin_resets SET completed_at = NOW()
    WHERE id = (
      SELECT id FROM hidden_pin_resets
      WHERE user_id = ${userId} AND cancelled_at IS NULL AND completed_at IS NULL
        AND verified_at IS NOT NULL AND ready_at <= NOW()
      ORDER BY created_at DESC LIMIT 1
    )
    RETURNING id
  `
  if (rows.length === 0) throw new HiddenPinResetError(409, 'Not ready yet', 'notReady')
}

export async function cancel(userId: string) {
  await sql`
    UPDATE hidden_pin_resets SET cancelled_at = NOW()
    WHERE user_id = ${userId} AND cancelled_at IS NULL AND completed_at IS NULL
  `
}

/// The warning email's link. Returns whether a request was cancelled.
export async function cancelByToken(token: string): Promise<boolean> {
  if (!/^[A-Za-z0-9_-]{20,64}$/.test(token)) return false
  const rows = await sql`
    UPDATE hidden_pin_resets SET cancelled_at = NOW()
    WHERE cancel_token_hash = ${hash(token)} AND cancelled_at IS NULL AND completed_at IS NULL
    RETURNING id
  `
  return rows.length > 0
}

type Block =
  | { text: string; muted?: boolean }
  | { code: string }
  | { button: string; href: string }

function emailHtml(lang: Lang, blocks: Block[]): string {
  const rows = blocks
    .map((block) => {
      if ('code' in block) {
        return `<tr><td style="font-size:32px;font-weight:700;letter-spacing:8px;padding:4px 0 20px;">${escapeHtml(block.code)}</td></tr>`
      }
      if ('button' in block) {
        const href = escapeHtml(block.href)
        return `<tr><td style="padding:4px 0 20px;"><a href="${href}" style="display:inline-block;background:#E5534B;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:13px 22px;border-radius:14px;">${escapeHtml(block.button)}</a></td></tr>`
      }
      const color = block.muted ? '#9BA4B1' : '#C9D0D9'
      const size = block.muted ? '12.5px' : '15px'
      return `<tr><td style="font-size:${size};line-height:1.5;color:${color};padding-bottom:16px;">${escapeHtml(block.text)}</td></tr>`
    })
    .join('\n        ')
  return `<!doctype html>
<html lang="${lang}">
<body style="margin:0;padding:24px;background:#111418;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#ECEFF3;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:480px;background:#191D23;border:1px solid #2A3038;border-radius:18px;padding:28px;" cellspacing="0" cellpadding="0">
        <tr><td style="font-size:20px;font-weight:700;padding-bottom:16px;">AllDocs</td></tr>
        ${rows}
      </table>
    </td></tr>
  </table>
</body>
</html>`
}

/// The page the warning email's cancel link opens.
export function cancelPage(lang: Lang, cancelled: boolean): string {
  const t = texts[lang]
  const title = cancelled ? t.cancelledTitle : t.invalidTitle
  const body = cancelled ? t.cancelledBody : t.invalidBody
  return `<!doctype html>
<html lang="${lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex">
  <title>AllDocs · ${escapeHtml(title)}</title>
</head>
<body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px 16px;box-sizing:border-box;background:#111418;color:#ECEFF3;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Helvetica,Arial,sans-serif;">
  <main style="width:100%;max-width:440px;">
    <div style="text-align:center;font-size:22px;font-weight:700;margin-bottom:20px;">AllDocs</div>
    <div style="background:#191D23;border:1px solid #2A3038;border-radius:22px;padding:24px;">
      <div style="width:48px;height:48px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:24px;font-weight:700;margin-bottom:14px;background:${cancelled ? 'rgba(95,191,119,0.16)' : 'rgba(229,83,75,0.16)'};color:${cancelled ? '#5FBF77' : '#E5534B'};">${cancelled ? '✓' : '!'}</div>
      <h1 style="font-size:21px;margin:0 0 10px;">${escapeHtml(title)}</h1>
      <p style="color:#9BA4B1;font-size:14px;line-height:1.5;margin:0;">${escapeHtml(body)}</p>
    </div>
  </main>
</body>
</html>`
}
