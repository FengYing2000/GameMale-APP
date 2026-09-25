/// 後台頁面（/admin）。單檔、不引外部資源；所有資料都用 textContent 塞，
/// 備註裡打了什麼 HTML 都不會被執行。手機上也要好操作。
const adminPageHtml = r'''<!DOCTYPE html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>GameMale 控制台</title>
<style>
:root{--bg:#0f1115;--card:#171a21;--line:#262b36;--text:#e6e8ee;--sub:#9aa3b5;--faint:#6b7385;
--brand:#8db943;--brand-bg:rgba(141,185,67,.14);--warn:#f0b14a;--warn-bg:rgba(240,177,74,.14);
--err:#ef6b6b;--err-bg:rgba(239,107,107,.13);--input:#10131a}
@media (prefers-color-scheme:light){:root{--bg:#f4f5f7;--card:#fff;--line:#e2e5ea;--text:#1b1f27;
--sub:#555e6e;--faint:#848c9a;--brand:#5b8a1c;--brand-bg:rgba(91,138,28,.12);--warn:#a35f00;
--warn-bg:rgba(224,142,11,.14);--err:#c43d3d;--err-bg:rgba(196,61,61,.1);--input:#fff}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 -apple-system,BlinkMacSystemFont,"Noto Sans TC","PingFang TC",sans-serif}
header{position:sticky;top:0;z-index:5;background:var(--bg);border-bottom:1px solid var(--line);
padding:12px 16px;display:flex;align-items:center;gap:12px}
header h1{font-size:17px;margin:0;flex:1}
main{max-width:860px;margin:0 auto;padding:16px}
nav{display:flex;gap:6px;margin-bottom:14px;overflow-x:auto}
nav button{flex:none}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px}
.card h2{font-size:15px;margin:0 0 12px}
.row{display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.row+.row{margin-top:10px}
.grow{flex:1;min-width:0}
.sub{color:var(--sub);font-size:13px}
.faint{color:var(--faint);font-size:12.5px}
label.field{display:block;margin-bottom:10px}
label.field span{display:block;font-size:13px;color:var(--sub);margin-bottom:4px}
input,textarea,select{width:100%;background:var(--input);color:var(--text);border:1px solid var(--line);
border-radius:8px;padding:9px 11px;font:inherit}
textarea{min-height:90px;resize:vertical}
input[type=checkbox]{width:auto}
button{background:var(--card);color:var(--text);border:1px solid var(--line);border-radius:8px;
padding:8px 13px;font:inherit;font-size:14px;cursor:pointer}
button.primary{background:var(--brand);border-color:var(--brand);color:#fff;font-weight:600}
button.danger{color:var(--err)}
button.on{background:var(--brand-bg);border-color:var(--brand);color:var(--brand);font-weight:600}
button:disabled{opacity:.5;cursor:default}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px}
.stat{background:var(--input);border:1px solid var(--line);border-radius:10px;padding:10px 12px}
.stat b{display:block;font-size:22px}
.badge{display:inline-block;font-size:12px;padding:1px 7px;border-radius:6px;background:var(--brand-bg);color:var(--brand)}
.badge.warn{background:var(--warn-bg);color:var(--warn)}
.badge.err{background:var(--err-bg);color:var(--err)}
.badge.dim{background:var(--input);color:var(--faint);border:1px solid var(--line)}
.code{font:600 16px ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;letter-spacing:.5px}
.switch{display:flex;align-items:center;gap:12px;padding:10px 0}
.switch+.switch{border-top:1px solid var(--line)}
.dev{border-top:1px dashed var(--line);margin-top:10px;padding-top:10px}
.dev .row{font-size:13px}
.banner{padding:10px 14px;border-radius:10px;margin-bottom:14px}
.banner.err{background:var(--err-bg);color:var(--err)}
.banner.ok{background:var(--brand-bg);color:var(--brand)}
.hide{display:none!important}
pre.notes{white-space:pre-wrap;margin:8px 0 0;font:inherit;font-size:13.5px;color:var(--sub)}
#toast{position:fixed;left:50%;bottom:24px;transform:translateX(-50%);background:#000c;color:#fff;
padding:9px 16px;border-radius:10px;font-size:14px;z-index:9;pointer-events:none;opacity:0;transition:opacity .2s}
</style>
</head>
<body>
<header><h1>GameMale 控制台</h1><button id="logout" class="hide">登出</button></header>
<main>
  <div id="login" class="card hide">
    <h2>登入後台</h2>
    <label class="field"><span>密碼</span><input id="pw" type="password" autocomplete="current-password"></label>
    <div class="row"><button class="primary" id="loginBtn">登入</button><span id="loginErr" class="sub"></span></div>
  </div>

  <div id="app" class="hide">
    <nav>
      <button data-tab="overview" class="on">總覽</button>
      <button data-tab="codes">測試碼</button>
      <button data-tab="releases">版本</button>
    </nav>

    <section id="tab-overview">
      <div class="grid" id="stats"></div>
      <div class="card" style="margin-top:14px">
        <h2>開關</h2>
        <div class="switch"><div class="grow"><b>需要測試碼</b>
          <div class="sub">開著＝測試期間，沒有有效測試碼的人不能用（網頁版在伺服器端擋、App 在啟動時擋）。關掉＝正式開放。</div></div>
          <button id="betaBtn"></button></div>
        <div class="switch"><div class="grow"><b>維護模式</b>
          <div class="sub">打開後所有人看到維護畫面；勾了「維護時可用」的測試碼不受影響。</div></div>
          <button id="mtBtn"></button></div>
        <label class="field" style="margin-top:8px"><span>維護訊息（顯示在維護畫面上）</span>
          <textarea id="mtMsg" placeholder="例如：伺服器更新中，預計 30 分鐘後恢復。"></textarea></label>
        <label class="field"><span>最低可用 build 號（低於的 App 強制更新；0＝不限）</span>
          <input id="minBuild" type="number" min="0" inputmode="numeric"></label>
        <button class="primary" id="saveSettings">儲存訊息與最低版本</button>
      </div>
    </section>

    <section id="tab-codes" class="hide">
      <div class="card">
        <h2>產生測試碼</h2>
        <label class="field"><span>備註（發給誰）</span><input id="cNote" maxlength="200"></label>
        <div class="grid">
          <label class="field"><span>數量</span><input id="cCount" type="number" min="1" max="100" value="1"></label>
          <label class="field"><span>裝置上限（0＝不限）</span><input id="cMax" type="number" min="0" value="2"></label>
          <label class="field"><span>到期日（空白＝不過期）</span><input id="cExp" type="date"></label>
        </div>
        <label class="row" style="margin-bottom:12px"><input id="cBypass" type="checkbox"> <span>維護時可用（自己測試用）</span></label>
        <button class="primary" id="createCodes">產生</button>
        <div id="created"></div>
      </div>
      <div class="row" style="margin-bottom:10px">
        <input id="cFilter" class="grow" placeholder="搜尋碼、備註、論壇暱稱或 UID">
      </div>
      <div id="codeList"></div>
    </section>

    <section id="tab-releases" class="hide">
      <div class="card">
        <h2 id="relTitle">發佈版本</h2>
        <div class="grid">
          <label class="field"><span>版本號</span><input id="rVer" placeholder="1.29.0"></label>
          <label class="field"><span>build 號</span><input id="rBuild" type="number" min="1"></label>
          <label class="field"><span>日期</span><input id="rDate" type="date"></label>
        </div>
        <label class="field"><span>更新內容（一行一條）</span><textarea id="rNotes"></textarea></label>
        <label class="field"><span>iOS 安裝檔網址（IPA）</span><input id="rIos" placeholder="https://github.com/…/GameMale-1.29.0.ipa"></label>
        <label class="field"><span>Android 安裝檔網址（APK）</span><input id="rAnd" placeholder="https://github.com/…/GameMale-1.29.0.apk"></label>
        <div class="row"><button class="primary" id="saveRelease">儲存</button><button id="resetRelease">清空</button></div>
        <p class="faint">通常不用手填：發版腳本會自動上傳安裝檔並登記在這裡。</p>
      </div>
      <div id="relList"></div>
    </section>
  </div>
</main>
<div id="toast"></div>
<script>
'use strict';
const $ = (id) => document.getElementById(id);
let state = null;

function h(tag, props, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props || {})) {
    if (k === 'class') el.className = v;
    else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (v !== false && v != null) el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return el;
}

function toast(msg) {
  const t = $('toast'); t.textContent = msg; t.style.opacity = 1;
  clearTimeout(toast.t); toast.t = setTimeout(() => (t.style.opacity = 0), 2200);
}

async function api(method, path, body) {
  const res = await fetch(path, {
    method, credentials: 'same-origin',
    headers: { 'content-type': 'application/json', 'x-gm-admin': '1' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let data = {};
  try { data = await res.json(); } catch (_) {}
  if (res.status === 401 && path !== '/api/admin/login') { showLogin(); throw new Error(data.error || '請先登入'); }
  if (!res.ok) throw new Error(data.error || data.message || ('HTTP ' + res.status));
  return data;
}

const fmt = (iso) => iso ? new Date(iso).toLocaleString('zh-TW', { hour12: false }) : '—';
const day = (iso) => iso ? new Date(iso).toLocaleDateString('zh-TW') : '';
const ago = (iso) => {
  if (!iso) return '—';
  const s = (Date.now() - new Date(iso)) / 1000;
  if (s < 90) return '剛剛';
  if (s < 3600) return Math.round(s / 60) + ' 分鐘前';
  if (s < 86400) return Math.round(s / 3600) + ' 小時前';
  return Math.round(s / 86400) + ' 天前';
};
const copy = async (text, what) => {
  try { await navigator.clipboard.writeText(text); toast('已複製' + (what || '')); }
  catch (_) { prompt('複製這段：', text); }
};

function showLogin() { $('app').classList.add('hide'); $('logout').classList.add('hide'); $('login').classList.remove('hide'); $('pw').focus(); }

async function load() {
  try {
    state = await api('GET', '/api/admin/state');
  } catch (e) { return; }
  $('login').classList.add('hide'); $('app').classList.remove('hide'); $('logout').classList.remove('hide');
  render();
}

function render() { renderOverview(); renderCodes(); renderReleases(); }

function renderOverview() {
  const s = state.settings;
  const devices = state.codes.flatMap((c) => c.devices);
  const dayAgo = Date.now() - 86400000;
  const active = devices.filter((d) => new Date(d.lastSeen) > dayAgo).length;
  const latest = state.releases[0];
  $('stats').replaceChildren(
    stat('測試碼', state.codes.filter((c) => c.enabled).length + ' / ' + state.codes.length, '啟用 / 全部'),
    stat('裝置', devices.length, '24 小時內用過 ' + active + ' 台'),
    stat('最新版本', latest ? latest.version : '—', latest ? 'build ' + latest.build : '還沒發佈'),
    stat('網頁版', state.webBuild ? 'build ' + state.webBuild : '—', '目前部署'),
  );
  const btn = (el, on, label) => { el.textContent = on ? '開啟中' : '已關閉'; el.className = on ? 'on' : ''; el.title = label; };
  btn($('betaBtn'), s.betaRequired);
  btn($('mtBtn'), s.maintenance);
  if (document.activeElement !== $('mtMsg')) $('mtMsg').value = s.maintenanceMessage || '';
  if (document.activeElement !== $('minBuild')) $('minBuild').value = s.minBuild || 0;
}
const stat = (label, value, sub) => h('div', { class: 'stat' }, h('span', { class: 'sub' }, label), h('b', {}, value), h('span', { class: 'faint' }, sub));

function codeStatus(c) {
  if (!c.enabled) return h('span', { class: 'badge err' }, '已停用');
  if (c.expiresAt && new Date(c.expiresAt) <= new Date()) return h('span', { class: 'badge warn' }, '已過期');
  return h('span', { class: 'badge' }, '有效');
}

function invite(c) {
  const o = location.origin;
  const lines = ['GameMale 測試碼：' + c.code, '', '網頁版：' + o + '（iPhone 用 Safari 開 → 分享 → 加入主畫面）'];
  const latest = state.releases[0];
  if (latest && latest.androidUrl) lines.push('Android：' + latest.androidUrl);
  if (latest && latest.iosUrl) lines.push('iOS（SideStore 來源）：' + o + '/api/app/source.json');
  lines.push('', '第一次打開會要求輸入測試碼。');
  return lines.join('\n');
}

function renderCodes() {
  const q = $('cFilter').value.trim().toUpperCase();
  const hit = (c) => c.code.includes(q) || (c.note || '').toUpperCase().includes(q) ||
    c.devices.some((d) => (d.forumName || '').toUpperCase().includes(q) || String(d.forumUid || '') === q);
  const list = state.codes
    .filter((c) => !q || hit(c))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  $('codeList').replaceChildren(...(list.length ? list.map(codeCard) : [h('p', { class: 'sub' }, '還沒有測試碼。')]));
}

function codeCard(c) {
  const max = c.maxDevices ? c.maxDevices : '不限';
  // 同一組碼綁的裝置登入了不同論壇帳號＝可能轉借給別人了
  const accounts = new Set(c.devices.map((d) => d.forumUid).filter(Boolean));
  return h('div', { class: 'card' },
    h('div', { class: 'row' },
      h('span', { class: 'code grow' }, c.code),
      codeStatus(c), c.bypass ? h('span', { class: 'badge warn' }, '維護時可用') : null,
      accounts.size > 1 ? h('span', { class: 'badge err', title: '這組碼的裝置登入了 ' + accounts.size + ' 個不同的論壇帳號' }, accounts.size + ' 個論壇帳號') : null),
    h('div', { class: 'row sub' },
      h('span', { class: 'grow' }, c.note || '（沒有備註）'),
      h('span', {}, '裝置 ' + c.devices.length + ' / ' + max),
      h('span', {}, c.expiresAt ? '到期 ' + day(c.expiresAt) : '不過期')),
    h('div', { class: 'row' },
      h('button', { onclick: () => copy(c.code, '測試碼') }, '複製碼'),
      h('button', { onclick: () => copy(invite(c), '邀請訊息') }, '複製邀請訊息'),
      h('button', { onclick: () => editCode(c) }, '編輯'),
      h('button', { onclick: () => patchCode(c, { enabled: !c.enabled }) }, c.enabled ? '停用' : '啟用'),
      h('button', { class: 'danger', onclick: () => delCode(c) }, '刪除')),
    ...c.devices.map(deviceRow.bind(null, c)));
}

function deviceRow(c, d) {
  const forum = d.forumUid
    ? h('a', { href: 'https://www.gamemale.com/space-uid-' + encodeURIComponent(d.forumUid) + '.html',
        target: '_blank', rel: 'noopener noreferrer', style: 'color:var(--brand)' },
        (d.forumName || '（沒有暱稱）') + '（UID ' + d.forumUid + '）')
    : h('span', { class: 'faint' }, '還沒登入過論壇');
  return h('div', { class: 'dev' },
    h('div', { class: 'row' },
      h('b', { class: 'grow' }, [d.model || platformName(d.platform), d.os, d.appVersion && ('v' + d.appVersion)].filter(Boolean).join(' · ')),
      h('span', { class: 'faint' }, '最後使用 ' + ago(d.lastSeen)),
      h('button', { class: 'danger', onclick: () => unbind(c, d) }, '解除')),
    h('div', { class: 'row' }, h('span', { class: 'sub' }, '論壇：'), forum),
    h('div', { class: 'faint' }, [platformName(d.platform), d.ip && ('IP ' + d.ip), '綁定於 ' + fmt(d.firstSeen), d.id.slice(0, 8)].filter(Boolean).join(' · ')));
}
const platformName = (p) => ({ ios: 'iOS', android: 'Android', web: '網頁版' }[p] || p || '未知');

async function patchCode(c, body) {
  try { const r = await api('PATCH', '/api/admin/codes/' + c.id, body); Object.assign(c, r.code); renderCodes(); renderOverview(); toast('已更新'); }
  catch (e) { toast(e.message); }
}
function editCode(c) {
  const note = prompt('備註', c.note || ''); if (note === null) return;
  const max = prompt('裝置上限（0＝不限）', c.maxDevices); if (max === null) return;
  const exp = prompt('到期日 YYYY-MM-DD（空白＝不過期）', c.expiresAt ? c.expiresAt.slice(0, 10) : ''); if (exp === null) return;
  const bypass = confirm('維護時可用？\n確定＝可用，取消＝不可用');
  patchCode(c, { note, maxDevices: parseInt(max, 10) || 0, expiresAt: exp.trim(), bypass });
}
async function delCode(c) {
  if (!confirm('刪除 ' + c.code + '？\n綁在上面的 ' + c.devices.length + ' 台裝置會立刻不能用。')) return;
  try { await api('DELETE', '/api/admin/codes/' + c.id); state.codes = state.codes.filter((x) => x.id !== c.id); render(); toast('已刪除'); }
  catch (e) { toast(e.message); }
}
async function unbind(c, d) {
  if (!confirm('解除這台裝置？對方要重新輸入測試碼才能用。')) return;
  try { const r = await api('DELETE', '/api/admin/codes/' + c.id + '/devices/' + encodeURIComponent(d.id)); Object.assign(c, r.code); render(); toast('已解除'); }
  catch (e) { toast(e.message); }
}

function renderReleases() {
  $('relList').replaceChildren(...(state.releases.length ? state.releases.map((r) => h('div', { class: 'card' },
    h('div', { class: 'row' },
      h('b', { class: 'grow' }, r.version + '（build ' + r.build + '）'),
      h('span', { class: 'faint' }, day(r.date))),
    h('div', { class: 'row' },
      r.iosUrl ? h('span', { class: 'badge' }, 'iOS') : h('span', { class: 'badge dim' }, '無 iOS'),
      r.androidUrl ? h('span', { class: 'badge' }, 'Android') : h('span', { class: 'badge dim' }, '無 Android'),
      h('span', { class: 'grow' }),
      h('button', { onclick: () => fillRelease(r) }, '編輯'),
      h('button', { class: 'danger', onclick: () => delRelease(r) }, '刪除')),
    r.notes ? h('pre', { class: 'notes' }, r.notes) : null)) : [h('p', { class: 'sub' }, '還沒有發佈任何版本。')]));
}
function fillRelease(r) {
  $('relTitle').textContent = '編輯 ' + r.version;
  $('rVer').value = r.version; $('rBuild').value = r.build; $('rDate').value = r.date.slice(0, 10);
  $('rNotes').value = r.notes || ''; $('rIos').value = r.iosUrl || ''; $('rAnd').value = r.androidUrl || '';
  window.scrollTo({ top: 0, behavior: 'smooth' });
}
function resetRelease() {
  $('relTitle').textContent = '發佈版本';
  for (const id of ['rVer', 'rBuild', 'rDate', 'rNotes', 'rIos', 'rAnd']) $(id).value = '';
}
async function delRelease(r) {
  if (!confirm('刪除 ' + r.version + '？（只刪登記，安裝檔不會動）')) return;
  try { await api('DELETE', '/api/admin/releases/' + r.build); state.releases = state.releases.filter((x) => x.build !== r.build); render(); }
  catch (e) { toast(e.message); }
}

$('loginBtn').onclick = async () => {
  $('loginErr').textContent = '';
  try { await api('POST', '/api/admin/login', { password: $('pw').value }); $('pw').value = ''; load(); }
  catch (e) { $('loginErr').textContent = e.message; }
};
$('pw').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('loginBtn').click(); });
$('logout').onclick = async () => { try { await api('POST', '/api/admin/logout'); } catch (_) {} showLogin(); };

for (const b of document.querySelectorAll('nav button')) {
  b.onclick = () => {
    for (const x of document.querySelectorAll('nav button')) x.classList.toggle('on', x === b);
    for (const s of document.querySelectorAll('main section')) s.classList.toggle('hide', s.id !== 'tab-' + b.dataset.tab);
  };
}

async function saveSettings(body, msg) {
  try { const r = await api('PUT', '/api/admin/settings', body); state.settings = r.settings; renderOverview(); toast(msg); }
  catch (e) { toast(e.message); }
}
$('betaBtn').onclick = () => {
  const on = !state.settings.betaRequired;
  if (!confirm(on ? '開啟「需要測試碼」？\n沒有有效測試碼的人會立刻不能用。' : '關閉「需要測試碼」？\n等於正式開放，所有人都能用。')) return;
  saveSettings({ betaRequired: on }, on ? '已開啟測試碼' : '已正式開放');
};
$('mtBtn').onclick = () => {
  const on = !state.settings.maintenance;
  if (!confirm(on ? '開啟維護模式？\n除了「維護時可用」的碼，所有人都會看到維護畫面。' : '結束維護？')) return;
  saveSettings({ maintenance: on, maintenanceMessage: $('mtMsg').value }, on ? '維護模式已開啟' : '維護已結束');
};
$('saveSettings').onclick = () => saveSettings({ maintenanceMessage: $('mtMsg').value, minBuild: parseInt($('minBuild').value, 10) || 0 }, '已儲存');

$('createCodes').onclick = async () => {
  try {
    const r = await api('POST', '/api/admin/codes', {
      note: $('cNote').value, count: parseInt($('cCount').value, 10) || 1,
      maxDevices: parseInt($('cMax').value, 10) || 0, expiresAt: $('cExp').value, bypass: $('cBypass').checked,
    });
    state.codes.push(...r.codes); render();
    $('created').replaceChildren(h('div', { class: 'banner ok', style: 'margin-top:12px' },
      h('div', {}, '產生了 ' + r.codes.length + ' 組：'),
      ...r.codes.map((c) => h('div', { class: 'row' }, h('span', { class: 'code grow' }, c.code),
        h('button', { onclick: () => copy(c.code, '測試碼') }, '複製'),
        h('button', { onclick: () => copy(invite(c), '邀請訊息') }, '邀請訊息')))));
    $('cNote').value = '';
  } catch (e) { toast(e.message); }
};
$('cFilter').addEventListener('input', renderCodes);

$('saveRelease').onclick = async () => {
  try {
    await api('POST', '/api/admin/releases', {
      version: $('rVer').value, build: parseInt($('rBuild').value, 10) || 0, date: $('rDate').value || undefined,
      notes: $('rNotes').value, iosUrl: $('rIos').value, androidUrl: $('rAnd').value,
    });
    toast('已儲存'); resetRelease(); load();
  } catch (e) { toast(e.message); }
};
$('resetRelease').onclick = resetRelease;

load();
</script>
</body>
</html>
''';
