import { escapeHtml } from '../password/password.service'
import { type Lang, texts } from './requests.texts'
import { MAX_FILE_BYTES } from './requests.service'

// The page a document request link opens: who is asking for what, and a
// file picker that uploads each file to POST /r/<token>/files. Same dark
// look as the password reset page; everything interpolated is escaped.
export function requestPage(options: {
  lang: Lang
  token: string
  nonce: string
  request: {
    title: string
    message: string | null
    requesterName: string
    expiresAt: Date
  } | null
}): string {
  const { lang, token, nonce, request } = options
  const t = texts[lang]
  const fill = (text: string, values: Record<string, string>) =>
    text.replace(/\{(\w+)\}/g, (_, key: string) => values[key] ?? '')

  const body = request
    ? `
      <p class="muted small">${escapeHtml(fill(t.asking, { name: request.requesterName }))}</p>
      <h1>${escapeHtml(request.title)}</h1>
      ${request.message ? `<p class="message">${escapeHtml(request.message)}</p>` : ''}
      <p class="muted">${escapeHtml(
        fill(t.until, {
          date: request.expiresAt.toLocaleDateString(lang === 'pt' ? 'pt-PT' : lang, {
            day: 'numeric', month: 'long', year: 'numeric',
          }),
        })
      )}</p>
      <div id="form">
        <label class="picker" for="files">
          <span class="plus">+</span>
          <span>${escapeHtml(t.choose)}</span>
          <span class="muted small">${escapeHtml(t.accepted)}</span>
        </label>
        <input id="files" type="file" multiple accept=".pdf,image/*,.doc,.docx,.xls,.xlsx,.ppt,.pptx,.odt,.ods,.txt">
        <ul id="list"></ul>
        <p id="error" class="error" role="alert" hidden></p>
        <button id="send" type="button" disabled>${escapeHtml(t.send)}</button>
        <p class="muted small lock">🔒 ${escapeHtml(fill(t.privacy, { name: request.requesterName }))}</p>
      </div>
      <div id="done" hidden>
        <div class="icon ok">✓</div>
        <h1>${escapeHtml(t.doneTitle)}</h1>
        <p class="muted">${escapeHtml(fill(t.doneBody, { name: request.requesterName }))}</p>
        <button id="more" type="button" class="secondary">${escapeHtml(t.sendMore)}</button>
      </div>`
    : `
      <div class="icon bad">!</div>
      <h1>${escapeHtml(t.invalidTitle)}</h1>
      <p class="muted">${escapeHtml(t.invalidBody)}</p>`

  const script = request
    ? `<script nonce="${nonce}">
  (function () {
    var token = ${JSON.stringify(token).replace(/</g, '\\u003c')};
    var maxBytes = ${MAX_FILE_BYTES};
    var t = ${JSON.stringify({
      send: t.send, sending: t.sending, tooBig: t.tooBig, badType: t.badType,
      tooMany: t.tooMany, failed: t.failed, invalid: t.invalidBody,
    }).replace(/</g, '\\u003c')};
    var input = document.getElementById('files');
    var list = document.getElementById('list');
    var send = document.getElementById('send');
    var error = document.getElementById('error');
    var chosen = [];
    function fail(message) { error.textContent = message; error.hidden = false; }
    function render() {
      list.textContent = '';
      chosen.forEach(function (file) {
        var item = document.createElement('li');
        item.textContent = file.name + ' · ' + Math.max(1, Math.round(file.size / 1024)) + ' KB';
        list.appendChild(item);
      });
      send.disabled = chosen.length === 0;
    }
    input.addEventListener('change', function () {
      error.hidden = true;
      Array.prototype.forEach.call(input.files, function (file) {
        if (file.size > maxBytes) return fail(t.tooBig.replace('{file}', file.name));
        chosen.push(file);
      });
      input.value = '';
      render();
    });
    function upload(index) {
      if (index >= chosen.length) {
        chosen = [];
        render();
        document.getElementById('form').hidden = true;
        document.getElementById('done').hidden = false;
        return;
      }
      var file = chosen[index];
      fetch('/r/' + encodeURIComponent(token) + '/files?name=' + encodeURIComponent(file.name), {
        method: 'POST',
        headers: { 'Content-Type': file.type || 'application/octet-stream' },
        body: file
      }).then(function (res) {
        if (res.ok) {
          list.children[index].className = 'sent';
          return upload(index + 1);
        }
        return res.json().catch(function () { return {}; }).then(function (data) {
          var message = t[data.code] || t.failed;
          send.disabled = false;
          send.textContent = t.send;
          chosen = chosen.slice(index);
          render();
          fail(message.replace('{file}', file.name));
        });
      }).catch(function () {
        send.disabled = false;
        send.textContent = t.send;
        fail(t.failed);
      });
    }
    send.addEventListener('click', function () {
      error.hidden = true;
      send.disabled = true;
      send.textContent = t.sending;
      upload(0);
    });
    document.getElementById('more').addEventListener('click', function () {
      document.getElementById('done').hidden = true;
      document.getElementById('form').hidden = false;
      send.textContent = t.send;
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
  <title>AllDocs · ${escapeHtml(request?.title ?? t.invalidTitle)}</title>
  <style nonce="${nonce}">
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: flex; align-items: center; justify-content: center;
      padding: 24px 16px; background: #111418; color: #ECEFF3;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
    main { width: 100%; max-width: 440px; }
    .brand { text-align: center; font-size: 22px; font-weight: 700; margin-bottom: 20px; }
    #card { background: #191D23; border: 1px solid #2A3038; border-radius: 22px; padding: 24px; }
    h1 { font-size: 21px; margin: 0 0 10px; line-height: 1.3; }
    .muted { color: #9BA4B1; font-size: 14px; line-height: 1.5; margin: 0 0 16px; }
    .small { font-size: 13px; margin-bottom: 6px; }
    .message { background: #111418; border-radius: 14px; padding: 12px 14px; margin: 0 0 14px;
      font-size: 14.5px; line-height: 1.5; white-space: pre-wrap; }
    .picker { display: flex; flex-direction: column; align-items: center; gap: 6px; padding: 22px 16px;
      border: 1.5px dashed #3A4250; border-radius: 18px; cursor: pointer; text-align: center; }
    .picker:hover { border-color: #5B8DEF; }
    .plus { width: 40px; height: 40px; border-radius: 50%; background: rgba(91, 141, 239, 0.16);
      color: #5B8DEF; display: flex; align-items: center; justify-content: center; font-size: 26px; }
    input[type=file] { display: none; }
    ul { list-style: none; padding: 0; margin: 14px 0 0; }
    li { padding: 10px 12px; background: #111418; border-radius: 12px; margin-bottom: 6px; font-size: 14px;
      overflow-wrap: anywhere; }
    li.sent::before { content: '✓ '; color: #5FBF77; font-weight: 700; }
    button { width: 100%; margin-top: 16px; padding: 14px; font-size: 15px; font-weight: 700; color: #fff;
      background: #5B8DEF; border: 0; border-radius: 16px; cursor: pointer; }
    button.secondary { background: #2A3038; }
    button:disabled { opacity: 0.55; cursor: default; }
    .lock { margin-top: 16px; }
    .error { color: #E5534B; font-size: 13.5px; margin: 12px 0 0; }
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
