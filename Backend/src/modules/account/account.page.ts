import { escapeHtml } from '../password/password.service'
import type { Lang } from '../requests/requests.texts'
import { texts } from './account.texts'

export type DeletionPage =
  | { kind: 'ask' }
  | { kind: 'sent' }
  | { kind: 'confirm'; token: string; email: string }
  | { kind: 'done' }
  | { kind: 'invalid' }

// The account deletion pages (/delete-account): ask for the link by email,
// "check your email", the confirmation (what goes, what stays, cancel the
// subscription first, a required checkbox), and the result. Plain forms, no
// script; the same dark look as the other AllDocs pages. Everything
// interpolated is escaped.
export function deletionPage(lang: Lang, nonce: string, page: DeletionPage): string {
  const t = texts[lang]
  const langField = `<input type="hidden" name="lang" value="${lang}">`
  let body: string
  switch (page.kind) {
    case 'ask':
      body = `
      <h1>${escapeHtml(t.askTitle)}</h1>
      <p class="muted">${escapeHtml(t.askIntro)}</p>
      <form method="post" action="/delete-account/request">
        ${langField}
        <label for="email">${escapeHtml(t.emailLabel)}</label>
        <input id="email" name="email" type="email" autocomplete="email" required autofocus>
        <button type="submit">${escapeHtml(t.sendLink)}</button>
      </form>`
      break
    case 'sent':
      body = `
      <div class="icon info">✉</div>
      <h1>${escapeHtml(t.sentTitle)}</h1>
      <p class="muted">${escapeHtml(t.sentBody)}</p>`
      break
    case 'confirm':
      body = `
      <h1>${escapeHtml(t.confirmTitle)}</h1>
      <p class="muted">${escapeHtml(t.confirmIntro.replace('{email}', page.email))}</p>
      <h2 class="bad-text">${escapeHtml(t.deletedHeading)}</h2>
      <ul>${t.deletedItems.map((item) => `<li>${escapeHtml(item)}</li>`).join('')}</ul>
      <h2>${escapeHtml(t.keptHeading)}</h2>
      <ul>${t.keptItems.map((item) => `<li>${escapeHtml(item)}</li>`).join('')}</ul>
      <div class="warning">
        ${escapeHtml(t.subscriptionWarning)}
        <a href="https://play.google.com/store/account/subscriptions" rel="noopener">${escapeHtml(t.manageGoogle)}</a>
        ·
        <a href="https://apps.apple.com/account/subscriptions" rel="noopener">${escapeHtml(t.manageApple)}</a>
      </div>
      <form method="post" action="/delete-account/confirm">
        ${langField}
        <input type="hidden" name="token" value="${escapeHtml(page.token)}">
        <label class="check">
          <input type="checkbox" name="confirm" value="yes" required>
          <span>${escapeHtml(t.checkbox)}</span>
        </label>
        <button type="submit" class="danger">${escapeHtml(t.deleteButton)}</button>
      </form>`
      break
    case 'done':
      body = `
      <div class="icon ok">✓</div>
      <h1>${escapeHtml(t.doneTitle)}</h1>
      <p class="muted">${escapeHtml(t.doneBody)}</p>`
      break
    case 'invalid':
      body = `
      <div class="icon bad">!</div>
      <h1>${escapeHtml(t.invalidTitle)}</h1>
      <p class="muted">${escapeHtml(t.invalidBody)}</p>
      <a class="button" href="/delete-account?lang=${lang}">${escapeHtml(t.askAgain)}</a>`
      break
  }

  return `<!doctype html>
<html lang="${lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex">
  <title>AllDocs · ${escapeHtml(t.askTitle)}</title>
  <style nonce="${nonce}">
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      padding: 24px 16px; background: #111418; color: #ECEFF3;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    main { width: 100%; max-width: 460px; }
    .brand { text-align: center; font-size: 22px; font-weight: 700; margin-bottom: 20px; }
    #card { background: #191D23; border: 1px solid #2A3038; border-radius: 22px; padding: 24px; }
    h1 { font-size: 21px; margin: 0 0 10px; line-height: 1.3; }
    h2 { font-size: 14px; margin: 18px 0 6px; text-transform: uppercase; letter-spacing: .04em; color: #9BA4B1; }
    .bad-text { color: #E5534B; }
    .muted { color: #9BA4B1; font-size: 14px; line-height: 1.5; margin: 0 0 16px; }
    ul { margin: 0; padding-left: 18px; font-size: 14px; line-height: 1.55; }
    li { margin-bottom: 4px; }
    .warning { margin: 18px 0 4px; padding: 12px 14px; border-radius: 14px; font-size: 13.5px; line-height: 1.5;
      background: rgba(214, 160, 59, 0.12); border: 1px solid rgba(214, 160, 59, 0.4); }
    .warning a { color: #F0B95A; font-weight: 700; }
    label { display: block; font-size: 13px; color: #9BA4B1; margin: 4px 0 6px; }
    input[type=email] { width: 100%; padding: 13px 14px; font-size: 16px; color: #ECEFF3; background: #111418;
      border: 1px solid #3A4250; border-radius: 14px; }
    input[type=email]:focus { outline: none; border-color: #5B8DEF; }
    .check { display: flex; gap: 10px; align-items: flex-start; margin-top: 18px; font-size: 14px; color: #ECEFF3;
      line-height: 1.45; cursor: pointer; }
    .check input { width: 20px; height: 20px; margin: 1px 0 0; flex: none; accent-color: #E5534B; }
    button, .button { display: block; width: 100%; margin-top: 16px; padding: 14px; font-size: 15px; font-weight: 700;
      color: #fff; background: #5B8DEF; border: 0; border-radius: 16px; cursor: pointer; text-align: center;
      text-decoration: none; }
    button.danger { background: #E5534B; }
    .icon { width: 48px; height: 48px; border-radius: 50%; display: flex; align-items: center;
      justify-content: center; font-size: 24px; font-weight: 700; margin-bottom: 14px; }
    .ok { background: rgba(95, 191, 119, 0.16); color: #5FBF77; }
    .bad { background: rgba(229, 83, 75, 0.16); color: #E5534B; }
    .info { background: rgba(91, 141, 239, 0.16); color: #5B8DEF; }
  </style>
</head>
<body>
  <main>
    <div class="brand">AllDocs</div>
    <div id="card">${body}
    </div>
  </main>
</body>
</html>`
}
