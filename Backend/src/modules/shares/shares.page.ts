import { escapeHtml } from '../password/password.service'
import type { Lang } from '../requests/requests.texts'
import type { OpenShare } from './shares.service'
import { texts } from './shares.texts'

// The page a secure share link opens: who shared what, until when, and a
// form (no script) that posts to /s/<token>/file to open or download it —
// with the access code when the share has one. Same dark look as the
// document request page; everything interpolated is escaped.
export function sharePage(options: {
  lang: Lang
  token: string
  nonce: string
  share: OpenShare | null
  error?: 'wrongCode' | null
}): string {
  const { lang, token, nonce, share, error } = options
  const t = texts[lang]
  const fill = (text: string, values: Record<string, string>) =>
    text.replace(/\{(\w+)\}/g, (_, key: string) => values[key] ?? '')
  const action = `/s/${encodeURIComponent(token)}/file`

  let body: string
  if (share && share.status === 'active') {
    const date = share.expiresAt.toLocaleDateString(lang === 'pt' ? 'pt-PT' : lang, {
      day: 'numeric', month: 'long', year: 'numeric',
    })
    const views =
      share.viewsLeft == null
        ? ''
        : share.viewsLeft <= 1
          ? t.viewLeft
          : fill(t.viewsLeft, { n: String(share.viewsLeft) })
    const size =
      share.sizeBytes >= 1024 * 1024
        ? `${(share.sizeBytes / (1024 * 1024)).toFixed(1)} MB`
        : `${Math.max(1, Math.round(share.sizeBytes / 1024))} KB`
    body = `
      <p class="muted small">${escapeHtml(fill(t.sharedBy, { name: share.ownerName }))}</p>
      <h1>${escapeHtml(share.title)}</h1>
      <div class="file"><span class="doc">▤</span><span>${escapeHtml(share.fileName)}<br><span class="muted small">${size}</span></span></div>
      <p class="muted">${escapeHtml(fill(t.until, { date }))}${views ? `<br>${escapeHtml(views)}` : ''}</p>
      <form method="post" action="${action}">
        ${
          share.needsCode
            ? `<label for="code">${escapeHtml(t.codeLabel)}</label>
        <input id="code" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]*" maxlength="8" required autofocus>
        <p class="muted small">${escapeHtml(fill(t.codeHint, { name: share.ownerName }))}</p>`
            : ''
        }
        ${
          error === 'wrongCode'
            ? `<p class="error" role="alert">${escapeHtml(fill(t.wrongCode, { n: String(share.attemptsLeft) }))}</p>`
            : ''
        }
        <button type="submit" name="mode" value="open">${escapeHtml(t.open)}</button>
        <button type="submit" name="mode" value="download" class="secondary">${escapeHtml(t.download)}</button>
      </form>
      <p class="muted small lock">🔒 ${escapeHtml(fill(t.privacy, { name: share.ownerName }))}</p>`
  } else if (share?.status === 'locked') {
    body = `
      <div class="icon bad">!</div>
      <h1>${escapeHtml(t.lockedTitle)}</h1>
      <p class="muted">${escapeHtml(t.lockedBody)}</p>`
  } else {
    body = `
      <div class="icon bad">!</div>
      <h1>${escapeHtml(t.invalidTitle)}</h1>
      <p class="muted">${escapeHtml(t.invalidBody)}</p>`
  }

  return `<!doctype html>
<html lang="${lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex">
  <title>AllDocs · ${escapeHtml(share?.status === 'active' ? share.title : t.invalidTitle)}</title>
  <style nonce="${nonce}">
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      padding: 24px 16px; background: #111418; color: #ECEFF3;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    main { width: 100%; max-width: 440px; }
    .brand { text-align: center; font-size: 22px; font-weight: 700; margin-bottom: 20px; }
    #card { background: #191D23; border: 1px solid #2A3038; border-radius: 22px; padding: 24px; }
    h1 { font-size: 21px; margin: 0 0 14px; line-height: 1.3; overflow-wrap: anywhere; }
    .muted { color: #9BA4B1; font-size: 14px; line-height: 1.5; margin: 0 0 16px; }
    .small { font-size: 13px; margin-bottom: 6px; }
    .file { display: flex; gap: 12px; align-items: center; background: #111418; border-radius: 14px;
      padding: 12px 14px; margin: 0 0 14px; font-size: 14.5px; overflow-wrap: anywhere; }
    .file .muted { margin: 0; }
    .doc { width: 36px; height: 36px; flex: none; border-radius: 10px; background: rgba(91, 141, 239, 0.16);
      color: #5B8DEF; display: flex; align-items: center; justify-content: center; font-size: 18px; }
    label { display: block; font-size: 13px; color: #9BA4B1; margin-bottom: 6px; }
    input { width: 100%; padding: 13px 14px; font-size: 20px; letter-spacing: 6px; text-align: center;
      color: #ECEFF3; background: #111418; border: 1px solid #3A4250; border-radius: 14px; margin-bottom: 8px; }
    input:focus { outline: none; border-color: #5B8DEF; }
    button { width: 100%; margin-top: 12px; padding: 14px; font-size: 15px; font-weight: 700; color: #fff;
      background: #5B8DEF; border: 0; border-radius: 16px; cursor: pointer; }
    button.secondary { background: #2A3038; }
    .lock { margin-top: 18px; }
    .error { color: #E5534B; font-size: 13.5px; margin: 8px 0 0; }
    .icon { width: 48px; height: 48px; border-radius: 50%; display: flex; align-items: center;
      justify-content: center; font-size: 24px; font-weight: 700; margin-bottom: 14px; }
    .bad { background: rgba(229, 83, 75, 0.16); color: #E5534B; }
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
