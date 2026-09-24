import nodemailer, { type Transporter } from 'nodemailer'

// Outgoing email over SMTP (any provider: Google Workspace, Zoho, Mailgun,
// SES...). Configured with SMTP_HOST/SMTP_PORT/SMTP_USER/SMTP_PASS and
// MAIL_FROM; without SMTP_HOST nothing is sent.
let transporter: Transporter | null = null

export function isMailConfigured(): boolean {
  return Boolean(process.env.SMTP_HOST)
}

function getTransporter(): Transporter {
  if (!transporter) {
    const port = Number(process.env.SMTP_PORT || 587)
    transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port,
      secure: port === 465,
      auth: process.env.SMTP_USER
        ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS }
        : undefined,
    })
  }
  return transporter
}

export interface Mail {
  to: string
  subject: string
  text: string
  html: string
}

export async function sendMail(mail: Mail): Promise<void> {
  if (!isMailConfigured()) {
    // Local development: show what would have been sent. Never in
    // production — the message can carry a password reset link.
    if (process.env.NODE_ENV !== 'production') {
      console.log(`[mail not configured] To: ${mail.to}\nSubject: ${mail.subject}\n\n${mail.text}`)
    } else {
      console.error('sendMail: SMTP is not configured, email not sent')
    }
    return
  }
  await getTransporter().sendMail({
    from: process.env.MAIL_FROM || process.env.SMTP_USER,
    ...mail,
  })
}
