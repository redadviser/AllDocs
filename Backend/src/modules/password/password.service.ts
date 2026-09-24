import crypto from 'crypto'
import { hashPassword } from '../../lib/auth'
import { sql } from '../../lib/db'
import { sendMail } from '../../lib/mailer'
import { type Lang, texts } from './password.texts'

const TOKEN_LIFETIME_MINUTES = 60
export const MIN_PASSWORD_LENGTH = 6

// One reset email per address per minute — stops the endpoint from being
// used to flood someone's inbox. In memory: good enough for one instance.
const RESEND_COOLDOWN_MS = 60_000
const lastRequestByEmail = new Map<string, number>()

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex')
}

// The link must point at our own server. Built from PUBLIC_URL, never from
// the request's Host header: a forged Host would otherwise make us email a
// link to someone else's site, handing them the victim's token.
export function publicBaseUrl(requestOrigin: string): string {
  const configured = process.env.PUBLIC_URL?.trim().replace(/\/+$/, '')
  if (configured) return configured
  if (process.env.NODE_ENV === 'production') {
    return 'https://all-docs-backend.triplanai.eupasoft.com'
  }
  return requestOrigin
}

// Sends the reset email when an account has this email. Callers answer the
// same way either way, so the endpoint can't be used to find out which
// emails have an account.
export async function requestPasswordReset(
  email: string,
  lang: Lang,
  requestOrigin: string
): Promise<void> {
  const normalized = email.trim().toLowerCase()
  if (!normalized.includes('@')) return

  const now = Date.now()
  const last = lastRequestByEmail.get(normalized)
  if (last && now - last < RESEND_COOLDOWN_MS) return
  lastRequestByEmail.set(normalized, now)

  const rows = await sql`SELECT id, email FROM users WHERE LOWER(email) = ${normalized}`
  if (rows.length === 0) return
  const user = rows[0]

  const token = crypto.randomBytes(32).toString('base64url')
  await sql`
    INSERT INTO password_resets (token_hash, user_id, expires_at)
    VALUES (
      ${hashToken(token)},
      ${user.id as string},
      NOW() + (${TOKEN_LIFETIME_MINUTES} * INTERVAL '1 minute')
    )
  `

  const link = `${publicBaseUrl(requestOrigin)}/reset-password?token=${token}&lang=${lang}`
  const t = texts[lang]
  await sendMail({
    to: user.email as string,
    subject: t.emailSubject,
    text: `${t.emailGreeting}\n\n${t.emailBody}\n\n${link}\n\n${t.emailIgnore}`,
    html: resetEmailHtml(lang, link),
  })
}

export async function isResetTokenValid(token: string): Promise<boolean> {
  if (!token) return false
  const rows = await sql`
    SELECT 1 FROM password_resets
    WHERE token_hash = ${hashToken(token)} AND used_at IS NULL AND expires_at > NOW()
  `
  return rows.length > 0
}

export class InvalidResetTokenError extends Error {}

// Sets the new password, burns every pending link of that account, and ends
// its sessions on all devices (someone who knew the old password shouldn't
// stay signed in).
export async function resetPassword(token: string, newPassword: string): Promise<void> {
  const passwordHash = await hashPassword(newPassword)
  await sql.begin(async (tx) => {
    const rows = await tx`
      UPDATE password_resets
      SET used_at = NOW()
      WHERE token_hash = ${hashToken(token)} AND used_at IS NULL AND expires_at > NOW()
      RETURNING user_id
    `
    if (rows.length === 0) throw new InvalidResetTokenError()
    const userId = rows[0].user_id as string

    await tx`UPDATE users SET password_hash = ${passwordHash} WHERE id = ${userId}`
    await tx`UPDATE password_resets SET used_at = NOW() WHERE user_id = ${userId} AND used_at IS NULL`
    await tx`DELETE FROM devices WHERE user_id = ${userId}`
  })
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

function resetEmailHtml(lang: Lang, link: string): string {
  const t = texts[lang]
  const href = escapeHtml(link)
  return `<!doctype html>
<html lang="${lang}">
<body style="margin:0;padding:24px;background:#111418;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#ECEFF3;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:480px;background:#191D23;border:1px solid #2A3038;border-radius:18px;padding:28px;" cellspacing="0" cellpadding="0">
        <tr><td style="font-size:20px;font-weight:700;padding-bottom:16px;">AllDocs</td></tr>
        <tr><td style="font-size:15px;line-height:1.5;padding-bottom:8px;">${escapeHtml(t.emailGreeting)}</td></tr>
        <tr><td style="font-size:15px;line-height:1.5;color:#C9D0D9;padding-bottom:24px;">${escapeHtml(t.emailBody)}</td></tr>
        <tr><td style="padding-bottom:24px;">
          <a href="${href}" style="display:inline-block;background:#5B8DEF;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:13px 22px;border-radius:14px;">${escapeHtml(t.emailButton)}</a>
        </td></tr>
        <tr><td style="font-size:12.5px;line-height:1.5;color:#9BA4B1;padding-bottom:12px;word-break:break-all;"><a href="${href}" style="color:#9BA4B1;">${href}</a></td></tr>
        <tr><td style="font-size:12.5px;line-height:1.5;color:#9BA4B1;">${escapeHtml(t.emailIgnore)}</td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`
}

export { escapeHtml }
