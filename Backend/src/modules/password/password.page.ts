import { escapeHtml, MIN_PASSWORD_LENGTH } from './password.service'
import { type Lang, texts } from './password.texts'

// The page opened from the reset email: a small form (new password twice)
// that posts to POST /api/auth/password/reset, in AllDocs' dark look.
// Everything interpolated is escaped; the token reaches the script as JSON.
export function resetPasswordPage(options: {
  lang: Lang
  token: string
  valid: boolean
  nonce: string
}): string {
  const { lang, token, valid, nonce } = options
  const t = texts[lang]
  const body = valid
    ? `
      <h1>${escapeHtml(t.pageTitle)}</h1>
      <p class="muted">${escapeHtml(t.pageIntro)}</p>
      <form id="form" novalidate>
        <label for="password">${escapeHtml(t.newPassword)}</label>
        <input id="password" type="password" autocomplete="new-password" minlength="${MIN_PASSWORD_LENGTH}" required autofocus>
        <label for="confirm">${escapeHtml(t.confirmPassword)}</label>
        <input id="confirm" type="password" autocomplete="new-password" minlength="${MIN_PASSWORD_LENGTH}" required>
        <p id="error" class="error" role="alert" hidden></p>
        <button id="submit" type="submit">${escapeHtml(t.save)}</button>
      </form>
      <div id="done" hidden>
        <div class="icon ok">✓</div>
        <h1>${escapeHtml(t.doneTitle)}</h1>
        <p class="muted">${escapeHtml(t.doneBody)}</p>
      </div>`
    : `
      <div class="icon bad">!</div>
      <h1>${escapeHtml(t.invalidTitle)}</h1>
      <p class="muted">${escapeHtml(t.invalidBody)}</p>`

  const script = valid
    ? `<script nonce="${nonce}">
  (function () {
    var token = ${JSON.stringify(token).replace(/</g, '\\u003c')};
    var messages = ${JSON.stringify({
      tooShort: t.tooShort,
      mismatch: t.mismatch,
      failed: t.failed,
      invalid: t.invalidBody,
    }).replace(/</g, '\\u003c')};
    var form = document.getElementById('form');
    var error = document.getElementById('error');
    var submit = document.getElementById('submit');
    function fail(message) { error.textContent = message; error.hidden = false; }
    form.addEventListener('submit', function (event) {
      event.preventDefault();
      error.hidden = true;
      var password = document.getElementById('password').value;
      var confirm = document.getElementById('confirm').value;
      if (password.length < ${MIN_PASSWORD_LENGTH}) return fail(messages.tooShort);
      if (password !== confirm) return fail(messages.mismatch);
      submit.disabled = true;
      fetch('/api/auth/password/reset', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token: token, password: password })
      }).then(function (res) {
        if (res.ok) {
          // Swap the form (and its title/intro) for the "done" message.
          form.hidden = true;
          document.querySelectorAll('#card > h1, #card > p.muted').forEach(function (el) { el.hidden = true; });
          document.getElementById('done').hidden = false;
          return;
        }
        submit.disabled = false;
        fail(res.status === 400 ? messages.invalid : messages.failed);
      }).catch(function () {
        submit.disabled = false;
        fail(messages.failed);
      });
    });
  })();
  </script>`
    : ''

  return `<!doctype html>
<html lang="${lang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex">
  <title>AllDocs · ${escapeHtml(t.pageTitle)}</title>
  <style nonce="${nonce}">
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      padding: 24px 16px; background: #111418; color: #ECEFF3;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    main { width: 100%; max-width: 420px; }
    .brand { text-align: center; font-size: 22px; font-weight: 700; margin-bottom: 20px; letter-spacing: 0.2px; }
    #card { background: #191D23; border: 1px solid #2A3038; border-radius: 22px; padding: 24px; }
    h1 { font-size: 20px; margin: 0 0 8px; }
    .muted { color: #9BA4B1; font-size: 14px; line-height: 1.5; margin: 0 0 20px; }
    label { display: block; font-size: 13px; color: #9BA4B1; margin: 14px 0 6px; }
    input { width: 100%; padding: 13px 14px; font-size: 16px; color: #ECEFF3; background: #111418;
      border: 1px solid #2A3038; border-radius: 14px; outline: none; }
    input:focus { border-color: #5B8DEF; }
    button { width: 100%; margin-top: 20px; padding: 14px; font-size: 15px; font-weight: 700; color: #fff;
      background: #5B8DEF; border: 0; border-radius: 16px; cursor: pointer; }
    button:disabled { opacity: 0.6; cursor: default; }
    .error { color: #E5534B; font-size: 13.5px; margin: 14px 0 0; }
    .icon { width: 48px; height: 48px; border-radius: 50%; display: flex; align-items: center;
      justify-content: center; font-size: 24px; font-weight: 700; margin-bottom: 14px; }
    .ok { background: rgba(95, 191, 119, 0.16); color: #5FBF77; }
    .bad { background: rgba(229, 83, 75, 0.16); color: #E5534B; }
    [hidden] { display: none !important; }
  </style>
</head>
<body>
  <main>
    <div class="brand">AllDocs</div>
    <div id="card">${body}
    </div>
  </main>
  ${script}
</body>
</html>`
}
