import crypto from 'crypto'
import { sql } from '../../lib/db'
import { removeStored } from '../../lib/file-vault'
import { sendMail } from '../../lib/mailer'
import { escapeHtml, publicBaseUrl } from '../password/password.service'
import type { Lang } from '../requests/requests.texts'
import { endSync } from '../sync/sync.service'
import { texts } from './account.texts'

// Deleting an account (Google Play requires it in the app and on the web):
// a link emailed to the account, valid for an hour, opens a page that
// shows what goes and asks for a last confirmation.

const LINK_MINUTES = 60
const RESEND_COOLDOWN_MS = 60_000
const lastRequestByUser = new Map<string, number>()

function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex')
}

/// a•••@gmail.com
export function maskEmail(email: string): string {
  const at = email.indexOf('@')
  if (at <= 1) return email
  return `${email[0]}${'•'.repeat(Math.min(6, Math.max(3, at - 1)))}${email.slice(at)}`
}

/// Emails the confirmation link to [user] (at most once a minute).
export async function sendDeletionLink(
  user: { id: string; email: string },
  lang: Lang,
  origin: string
) {
  const now = Date.now()
  const last = lastRequestByUser.get(user.id)
  if (last && now - last < RESEND_COOLDOWN_MS) return
  lastRequestByUser.set(user.id, now)

  const token = crypto.randomBytes(32).toString('base64url')
  await sql`
    INSERT INTO account_deletions (token_hash, user_id, expires_at)
    VALUES (${hashToken(token)}, ${user.id}, NOW() + (${LINK_MINUTES} * INTERVAL '1 minute'))
  `
  const link = `${publicBaseUrl(origin)}/delete-account?token=${token}&lang=${lang}`
  const t = texts[lang]
  const body = t.emailBody.replace('{email}', user.email)
  await sendMail({
    to: user.email,
    subject: t.emailSubject,
    text: `${body}\n\n${link}\n\n${t.emailIgnore}`,
    html: emailHtml(lang, body, t.emailButton, link, t.emailIgnore),
  })
}

/// The public form: sends the link if [email] has an account, and answers
/// the same either way (so it can't be used to find out who has one).
export async function sendDeletionLinkForEmail(email: string, lang: Lang, origin: string) {
  const normalized = email.trim().toLowerCase()
  if (!normalized.includes('@')) return
  const rows = await sql`SELECT id, email FROM users WHERE LOWER(email) = ${normalized}`
  if (rows.length === 0) return
  await sendDeletionLink({ id: rows[0].id as string, email: rows[0].email as string }, lang, origin)
}

/// The account a link is for, while it's valid.
export async function accountForToken(token: string) {
  if (!/^[A-Za-z0-9_-]{30,64}$/.test(token)) return null
  const rows = await sql`
    SELECT u.id, u.email FROM account_deletions d
    JOIN users u ON u.id = d.user_id
    WHERE d.token_hash = ${hashToken(token)} AND d.used_at IS NULL AND d.expires_at > NOW()
  `
  return rows[0] ? { id: rows[0].id as string, email: rows[0].email as string } : null
}

/// Deletes the account a valid link is for. Returns whether it did.
export async function deleteWithToken(token: string): Promise<boolean> {
  const account = await accountForToken(token)
  if (!account) return false
  await sql`UPDATE account_deletions SET used_at = NOW() WHERE token_hash = ${hashToken(token)}`
  await deleteAccount(account.id)
  return true
}

/// Everything the server has for the account: files on disk first (rows
/// only point at them), then the account, whose rows cascade.
export async function deleteAccount(userId: string) {
  await endSync(userId)
  const shareFiles = await sql`
    SELECT stored_name FROM document_shares WHERE user_id = ${userId} AND stored_name IS NOT NULL
  `
  const requestFiles = await sql`
    SELECT f.stored_name FROM document_request_files f
    JOIN document_requests r ON r.id = f.request_id
    WHERE r.user_id = ${userId} AND f.stored_name IS NOT NULL
  `
  for (const file of [...shareFiles, ...requestFiles]) {
    await removeStored(file.stored_name as string).catch((error) =>
      console.error('Removing a stored file of a deleted account failed:', error)
    )
  }
  // Sessions aren't tied to the account by a foreign key.
  await sql`DELETE FROM devices WHERE user_id = ${userId}`
  await sql`DELETE FROM users WHERE id = ${userId}`
  lastRequestByUser.delete(userId)
}

function emailHtml(lang: Lang, body: string, button: string, link: string, note: string): string {
  const href = escapeHtml(link)
  return `<!doctype html>
<html lang="${lang}">
<body style="margin:0;padding:24px;background:#111418;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#ECEFF3;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
    <tr><td align="center">
      <table role="presentation" width="100%" style="max-width:480px;background:#191D23;border:1px solid #2A3038;border-radius:18px;padding:28px;" cellspacing="0" cellpadding="0">
        <tr><td style="font-size:20px;font-weight:700;padding-bottom:16px;">AllDocs</td></tr>
        <tr><td style="font-size:15px;line-height:1.5;color:#C9D0D9;padding-bottom:24px;">${escapeHtml(body)}</td></tr>
        <tr><td style="padding-bottom:24px;">
          <a href="${href}" style="display:inline-block;background:#E5534B;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:13px 22px;border-radius:14px;">${escapeHtml(button)}</a>
        </td></tr>
        <tr><td style="font-size:12.5px;line-height:1.5;color:#9BA4B1;">${escapeHtml(note)}</td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`
}
