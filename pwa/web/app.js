'use strict';

// ── 小工具 ───────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const main = $('main');
const logLines = [];
function log(m) {
  logLines.push(new Date().toTimeString().slice(0, 8) + '  ' + m);
  const el = $('log');
  if (el) { el.textContent = logLines.join('\n'); el.scrollTop = el.scrollHeight; }
}

function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

const isStandalone = window.navigator.standalone === true ||
  window.matchMedia('(display-mode: standalone)').matches;
const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

// 認證走 HttpOnly cookie，前端不碰 token；credentials 一定要 same-origin
async function api(path, opts = {}) {
  const res = await fetch(path, Object.assign({ credentials: 'same-origin' }, opts, {
    headers: Object.assign({ 'content-type': 'application/json' }, opts.headers || {}),
  }));
  let data = {};
  try { data = await res.json(); } catch (_) {}
  if (!res.ok) {
    const err = new Error(data.error || ('HTTP ' + res.status));
    err.status = res.status;
    throw err;
  }
  return data;
}

function loading(msg) {
  main.innerHTML = '<div class="center"><div class="spin"></div>' + esc(msg || '載入中…') + '</div>';
}
function errorBox(e, retry) {
  main.innerHTML = '<div class="center">' + esc(e.message) +
    '<br><br><button class="b ghost" style="max-width:200px;margin:0 auto" id="rt">重試</button></div>';
  if (retry) $('rt').onclick = retry;
}

// ── 狀態 ─────────────────────────────────────────────────────
let me = null;              // /api/me 的結果，null = 沒登入
let vapidKey = null, registration = null;
const cache = {};           // 各頁的捲動位置

// ── 路由 ─────────────────────────────────────────────────────
// 用 hash 路由：PWA 從主畫面開起來是獨立視窗，hash 換頁不會觸發整頁重載，
// 也讓 iOS 的返回手勢有東西可退。
const routes = [
  [/^#\/$/,                 () => viewIndex()],
  [/^#\/f\/(\d+)(?:\/(\d+))?$/, (fid, page) => viewForum(+fid, +(page || 1))],
  [/^#\/t\/(\d+)(?:\/(\d+))?$/, (tid, page) => viewThread(+tid, +(page || 1))],
  [/^#\/pm$/,               () => viewPmList()],
  [/^#\/pm\/(\d+)$/,        (uid) => viewPmChat(+uid)],
  [/^#\/notice$/,           () => viewNotice()],
  [/^#\/me$/,               () => viewMe()],
  [/^#\/settings$/,         () => viewSettings()],
  [/^#\/sign$/,             () => viewSign()],
];

function go(hash) { location.hash = hash; }

function setTitle(t, canBack) {
  $('title').textContent = t;
  $('back').hidden = !canBack;
}

async function route() {
  const h = location.hash || '#/';
  // 記住上一頁捲到哪，返回時還原
  if (route.last) cache[route.last] = window.scrollY;
  route.last = h;

  if (!me) { renderLogin(); return; }
  $('nav').hidden = false;

  for (const [re, fn] of routes) {
    const m = h.match(re);
    if (m) {
      try { await fn(...m.slice(1)); }
      catch (e) {
        if (e.status === 401) { me = null; renderLogin(); return; }
        errorBox(e, route);
      }
      const y = cache[h];
      window.scrollTo(0, /^#\/(f|t)\//.test(h) ? (y || 0) : (y || 0));
      syncNav();
      return;
    }
  }
  go('#/');
}

function syncNav() {
  const h = location.hash || '#/';
  const top = h === '#/' ? '#/' : h.startsWith('#/pm') ? '#/pm'
    : h.startsWith('#/notice') ? '#/notice'
    : (h.startsWith('#/me') || h === '#/settings' || h === '#/sign') ? '#/me' : '';
  for (const b of document.querySelectorAll('nav button')) {
    b.classList.toggle('on', b.dataset.go === top);
  }
}

$('back').onclick = () => history.back();
$('refresh').onclick = () => route();
for (const b of document.querySelectorAll('nav button')) {
  b.onclick = () => go(b.dataset.go);
}
window.addEventListener('hashchange', route);

// 站內連結攔下來自己導頁，不要跳出去開瀏覽器
main.addEventListener('click', (ev) => {
  const a = ev.target.closest('a');
  if (!a) return;
  const href = a.getAttribute('href') || '';
  const m = href.match(/thread-(\d+)|tid=(\d+)/);
  const f = href.match(/forum-(\d+)|fid=(\d+)/);
  if (m) { ev.preventDefault(); go('#/t/' + (m[1] || m[2])); }
  else if (f) { ev.preventDefault(); go('#/f/' + (f[1] || f[2])); }
  else if (/^https?:/.test(href)) { a.target = '_blank'; a.rel = 'noopener'; }
});

// ── 紅點 ─────────────────────────────────────────────────────
function renderBadges() {
  const set = (el, n) => { el.hidden = !n; el.textContent = n > 99 ? '99+' : n; };
  set($('bPm'), me ? me.pm : 0);
  set($('bNotice'), me ? me.notice : 0);
}

// ── 首頁：版塊列表 ───────────────────────────────────────────
async function viewIndex() {
  setTitle('GameMale', false);
  loading();
  const d = await api('/api/index');
  let h = '';

  if (d.sign) {
    h += '<div class="card tap" onclick="location.hash=\'#/sign\'">' +
      '<div class="frow"><div class="body"><b>' +
      (d.sign.signed ? '今天已簽到' : '今天還沒簽到') + '</b>' +
      '<small>' + esc(d.sign.title || d.sign.label || '') + '</small></div>' +
      '<span style="color:var(--dim)">›</span></div></div>';
  }

  for (const g of d.groups) {
    h += '<div class="sec">' + esc(g.name) + '</div>';
    for (const f of g.forums) {
      h += '<div class="card tap" onclick="location.hash=\'#/f/' + f.fid + '\'">' +
        '<div class="frow">' +
        (f.icon ? '<img class="ico" src="' + esc(f.icon) + '" loading="lazy" alt="">' : '') +
        '<div class="body"><b>' + esc(f.name) + '</b>' +
        '<small>' + esc(f.desc || '') + '</small>' +
        (f.threads ? '<small>主題 ' + esc(f.threads) +
          (f.posts ? ' · 帖數 ' + esc(f.posts) : '') + '</small>' : '') +
        '</div><span style="color:var(--dim)">›</span></div>';
      if (f.subforums && f.subforums.length) {
        h += '<div style="margin-top:8px;display:flex;flex-wrap:wrap;gap:6px">' +
          f.subforums.map((s) =>
            '<span class="tag" onclick="event.stopPropagation();location.hash=\'#/f/' +
            s.fid + '\'">' + esc(s.name) + '</span>').join('') + '</div>';
      }
      h += '</div>';
    }
  }
  main.innerHTML = h || '<div class="center">沒有可看的版塊</div>';
}

// ── 版塊：主題列表 ───────────────────────────────────────────
function pagerHtml(p, hrefFn) {
  if (!p) return '';
  const prev = p.hasPrev || p.page > 1;
  const next = p.hasNext || (p.numbered && p.page < p.total);
  if (!prev && !next) return '';
  return '<div class="pager">' +
    '<button ' + (prev ? '' : 'disabled ') + 'data-pg="' + (p.page - 1) + '">‹ 上一頁</button>' +
    '<span>' + p.page + (p.numbered && p.total > 1 ? ' / ' + p.total : '') + '</span>' +
    '<button ' + (next ? '' : 'disabled ') + 'data-pg="' + (p.page + 1) + '">下一頁 ›</button>' +
    '</div>';
}
function wirePager(hrefFn) {
  for (const b of main.querySelectorAll('[data-pg]')) {
    b.onclick = () => { window.scrollTo(0, 0); go(hrefFn(+b.dataset.pg)); };
  }
}

async function viewForum(fid, page) {
  setTitle('版塊', true);
  loading();
  const d = await api('/api/forum/' + fid + '?page=' + page);
  setTitle(d.name || '版塊', true);

  if (d.requiresLogin) {
    main.innerHTML = '<div class="center">這個版塊需要權限才能看</div>';
    return;
  }
  let h = '';
  if (d.message) h += '<div class="note err">' + esc(d.message) + '</div>';
  if (d.subforums && d.subforums.length) {
    h += '<div class="card"><div style="display:flex;flex-wrap:wrap;gap:6px">' +
      d.subforums.map((s) => '<span class="tag" onclick="location.hash=\'#/f/' +
        s.fid + '\'">' + esc(s.name) + '</span>').join('') + '</div></div>';
  }

  h += '<div class="card">';
  if (!d.list.length) h += '<div class="center">這一頁沒有主題</div>';
  for (const t of d.list) {
    h += '<div class="trow" onclick="location.hash=\'#/t/' + t.tid + '\'">' +
      '<div class="t">' +
      (t.type ? '<span class="tag">' + esc(t.type) + '</span>' : '') +
      esc(t.title) + '</div>' +
      '<div class="m"><span>' + esc(t.author || '') + '</span>' +
      (t.date ? '<span>' + esc(t.date) + '</span>' : '') +
      '<span>' + t.replies + ' 回覆</span>' +
      '<span>' + t.views + ' 看過</span></div></div>';
  }
  h += '</div>';
  h += pagerHtml(d.pager);
  main.innerHTML = h;
  wirePager((p) => '#/f/' + fid + '/' + p);
}

// ── 主題：貼文 ───────────────────────────────────────────────
async function viewThread(tid, page) {
  setTitle('主題', true);
  loading();
  const d = await api('/api/thread/' + tid + '?page=' + page);
  setTitle(d.title || '主題', true);

  if (d.requiresLogin) {
    main.innerHTML = '<div class="center">這篇需要權限才能看</div>';
    return;
  }

  let h = '<div class="card"><div style="font-size:17px;font-weight:600;' +
    'line-height:1.45;margin-bottom:2px">' + esc(d.title) + '</div>' +
    '<small style="color:var(--dim)">' + esc(d.forumName || '') + '</small></div>';

  if (d.poll) {
    h += '<div class="card"><b>' + esc(d.poll.title || '投票') + '</b>' +
      '<small style="display:block;color:var(--dim);margin-bottom:8px">' +
      esc(d.poll.info || '') + '</small>';
    for (const o of d.poll.options) {
      h += '<div style="margin:7px 0"><div style="display:flex;justify-content:space-between;font-size:14px">' +
        '<span>' + esc(o.text) + '</span><span style="color:var(--dim)">' +
        esc(o.percent) + '</span></div>' +
        '<div style="height:6px;border-radius:3px;background:#242a36;margin-top:3px">' +
        '<div style="height:100%;border-radius:3px;background:var(--accent);width:' +
        esc(o.percent || '0%') + '"></div></div></div>';
    }
    h += '</div>';
  }

  h += '<div class="card">';
  for (const p of d.posts) {
    h += '<div class="post">' +
      '<div class="phead">' +
      (p.avatar ? '<img src="' + esc(p.avatar) + '" loading="lazy" alt="">' : '') +
      '<div class="who"><b>' + esc(p.author) + '</b><small>' + esc(p.time) + '</small></div>' +
      '<span class="floor">' + esc(p.floor) + '</span></div>' +
      '<div class="pbody">' + p.html + '</div>' +
      (p.signature ? '<div class="sig">' + p.signature + '</div>' : '');
    if (p.comments && p.comments.length) {
      h += '<div class="cmts">' + p.comments.map((c) =>
        '<div class="cmt"><b>' + esc(c.name) + '</b>：' + esc(c.text) + '</div>').join('') +
        '</div>';
    }
    h += '</div>';
  }
  h += '</div>';
  h += pagerHtml(d.pager);

  h += '<div class="composer"><textarea id="rep" placeholder="回覆這篇…"></textarea>' +
    '<button id="repBtn">送出</button></div><div id="repNote"></div>';

  main.innerHTML = h;
  wirePager((p) => '#/t/' + tid + '/' + p);

  $('repBtn').onclick = async () => {
    const msg = $('rep').value.trim();
    if (!msg) return;
    $('repBtn').disabled = true;
    try {
      const res = await api('/api/reply', {
        method: 'POST',
        body: JSON.stringify({ fid: d.fid, tid: d.tid, message: msg }),
      });
      $('repNote').innerHTML = '<div class="note ' + (res.ok ? 'good' : 'err') + '">' +
        esc(res.message) + '</div>';
      if (res.ok) { $('rep').value = ''; setTimeout(() => route(), 700); }
    } catch (e) {
      $('repNote').innerHTML = '<div class="note err">' + esc(e.message) + '</div>';
    } finally { $('repBtn').disabled = false; }
  };
}

// ── 私訊 ─────────────────────────────────────────────────────
async function viewPmList() {
  setTitle('訊息', false);
  loading();
  const d = await api('/api/pm');
  let h = '';
  if (d.message) h += '<div class="note err">' + esc(d.message) + '</div>';
  h += '<div class="card">';
  if (!d.items.length) h += '<div class="center">還沒有私訊</div>';
  for (const p of d.items) {
    h += '<div class="trow" onclick="location.hash=\'#/pm/' + p.touid + '\'">' +
      '<div class="frow">' +
      (p.avatar ? '<img class="ico" style="border-radius:17px" src="' +
        esc(p.avatar) + '" loading="lazy" alt="">' : '') +
      '<div class="body"><b>' + esc(p.name) +
      (p.unread ? ' <span class="tag hot">' + p.unread + '</span>' : '') + '</b>' +
      '<small>' + esc(p.last || '') + '</small></div>' +
      '<small style="color:var(--dim);flex:none">' + esc(p.time || '') + '</small>' +
      '</div></div>';
  }
  h += '</div>';
  main.innerHTML = h;
  // 進來看過就把紅點消掉，不用等下一次輪詢
  if (me && me.pm) { me.pm = 0; renderBadges(); }
}

async function viewPmChat(uid) {
  setTitle('對話', true);
  loading();
  const d = await api('/api/pm/' + uid);
  setTitle(d.title || '對話', true);

  let h = '<div>';
  for (const m of d.messages) {
    h += '<div class="msg' + (m.mine ? ' me' : '') + '">' +
      (m.avatar ? '<img class="av" src="' + esc(m.avatar) + '" loading="lazy" alt="">' : '') +
      '<div><div class="b">' + m.html + '</div>' +
      '<div class="tm">' + esc(m.time || '') + '</div></div></div>';
  }
  h += '</div>';
  h += '<div class="composer"><textarea id="pm" placeholder="輸入訊息…"></textarea>' +
    '<button id="pmBtn">送出</button></div><div id="pmNote"></div>';
  main.innerHTML = h;
  window.scrollTo(0, document.body.scrollHeight);

  $('pmBtn').onclick = async () => {
    const msg = $('pm').value.trim();
    if (!msg) return;
    $('pmBtn').disabled = true;
    try {
      const res = await api('/api/pm/' + uid, {
        method: 'POST',
        body: JSON.stringify({ message: msg, pmid: d.pmid }),
      });
      if (res.ok) { $('pm').value = ''; await viewPmChat(uid); }
      else $('pmNote').innerHTML = '<div class="note err">' + esc(res.message) + '</div>';
    } catch (e) {
      $('pmNote').innerHTML = '<div class="note err">' + esc(e.message) + '</div>';
    } finally { $('pmBtn').disabled = false; }
  };
}

// ── 通知 ─────────────────────────────────────────────────────
const NOTICE_TABS = [
  ['mypost', '回覆我的'], ['interactive', '互動'],
  ['system', '系統'], ['manage', '管理'],
];
async function viewNotice(view) {
  setTitle('通知', false);
  const cur = view || (location.hash.split('?')[1] || 'mypost');
  loading();
  const d = await api('/api/notice?view=' + encodeURIComponent(cur));

  let h = '<div style="display:flex;gap:6px;overflow-x:auto;padding-bottom:8px">' +
    NOTICE_TABS.map(([k, n]) =>
      '<button class="tag" data-nv="' + k + '" style="padding:6px 12px;font-size:13px' +
      (k === cur ? ';background:var(--accent);color:#fff' : '') + '">' +
      n + '</button>').join('') + '</div>';

  h += '<div class="card">';
  if (!d.items.length) h += '<div class="center">沒有通知</div>';
  for (const n of d.items) {
    h += '<div class="trow"' +
      (n.tid ? ' onclick="location.hash=\'#/t/' + n.tid + '\'"' : '') + '>' +
      '<div class="frow">' +
      (n.avatar ? '<img class="ico" style="border-radius:17px" src="' +
        esc(n.avatar) + '" loading="lazy" alt="">' : '') +
      '<div class="body"><div style="font-size:14px">' + esc(n.text) + '</div>' +
      '<small>' + esc(n.time || '') + '</small></div></div></div>';
  }
  h += '</div>';
  main.innerHTML = h;
  for (const b of main.querySelectorAll('[data-nv]')) {
    b.onclick = () => viewNotice(b.dataset.nv);
  }
  if (me && me.notice) { me.notice = 0; renderBadges(); }
}

// ── 簽到 ─────────────────────────────────────────────────────
async function viewSign() {
  setTitle('簽到', true);
  loading();
  const d = await api('/api/sign');
  let h = '<div class="card"><div style="font-size:16px;font-weight:600">' +
    (d.signed ? '今天已經簽到了' : '今天還沒簽到') + '</div>' +
    (d.level ? '<small style="color:var(--dim)">' + esc(d.level) + '</small>' : '') +
    '</div>';
  if (d.stats && d.stats.length) {
    h += '<div class="card">' + d.stats.map((s) =>
      '<div class="srow"><div class="k"><b>' + esc(s.label) + '</b></div>' +
      '<span style="color:var(--dim)">' + esc(s.value) + '</span></div>').join('') +
      '</div>';
  }
  if (!d.signed) h += '<button class="b" id="signBtn">立刻簽到</button>';
  h += '<div id="signNote"></div>';
  main.innerHTML = h;

  const btn = $('signBtn');
  if (btn) btn.onclick = async () => {
    btn.disabled = true;
    try {
      const res = await api('/api/sign/do', { method: 'POST' });
      $('signNote').innerHTML = '<div class="note ' + (res.ok ? 'good' : 'err') + '">' +
        esc(res.message) + '</div>';
      if (res.ok) setTimeout(() => viewSign(), 800);
    } catch (e) {
      $('signNote').innerHTML = '<div class="note err">' + esc(e.message) + '</div>';
    } finally { btn.disabled = false; }
  };
}

// ── 我的 ─────────────────────────────────────────────────────
async function viewMe() {
  setTitle('我的', false);
  me = await api('/api/me');
  renderBadges();
  const expired = me.cookieStatus === 'expired';
  main.innerHTML =
    '<div class="card"><div class="srow"><div class="dot ' +
      (expired ? 'bad' : 'ok') + '"></div><div class="k"><b>' + esc(me.username) +
      '</b><small>' + (expired ? '登入已過期，請重新登入' : '論壇登入中') +
      '</small></div></div>' +
      '<div class="srow"><div class="k"><b>未讀</b><small>提醒 ' + me.notice +
      ' · 私訊 ' + me.pm + '</small></div></div>' +
      '<div class="srow"><div class="k"><b>上次檢查</b><small>' +
      (me.lastCheckedAt ? new Date(me.lastCheckedAt).toLocaleString('zh-TW', { hour12: false }) : '還沒查過') +
      '</small></div></div></div>' +
    '<div class="card tap" onclick="location.hash=\'#/sign\'">' +
      '<div class="frow"><div class="body"><b>簽到</b></div>' +
      '<span style="color:var(--dim)">›</span></div></div>' +
    '<div class="card tap" onclick="location.hash=\'#/settings\'">' +
      '<div class="frow"><div class="body"><b>通知設定</b>' +
      '<small>提醒、私訊、自動簽到</small></div>' +
      '<span style="color:var(--dim)">›</span></div></div>' +
    '<button class="b danger" id="outBtn">登出</button>';

  $('outBtn').onclick = async () => {
    try { await api('/api/logout', { method: 'POST' }); } catch (_) {}
    me = null;
    $('nav').hidden = true;
    renderLogin();
  };
}

// ── 通知設定 ─────────────────────────────────────────────────
async function viewSettings() {
  setTitle('通知設定', true);
  const perm = ('Notification' in window) ? Notification.permission : 'unsupported';
  const sub = registration ? await registration.pushManager.getSubscription() : null;
  const bound = !!sub && me.devices > 0;
  const blocked = isIOS && !isStandalone;

  let h = '<div class="card"><div class="srow"><div class="dot ' +
    (bound && perm === 'granted' ? 'ok' : perm === 'denied' ? 'bad' : 'idle') +
    '"></div><div class="k"><b>這台裝置的推播</b><small>' +
    (perm === 'denied' ? '被拒絕 —— 要到系統設定裡改回來'
      : bound && perm === 'granted' ? '已開啟，共 ' + me.devices + ' 台裝置'
      : '尚未開啟') + '</small></div></div>';
  if (!(bound && perm === 'granted')) {
    h += '<button class="b" id="enBtn"' + (blocked || perm === 'denied' ? ' disabled' : '') +
      '>開啟通知</button>';
  } else {
    h += '<button class="b ghost" id="testBtn">送一則測試通知</button>';
  }
  if (blocked) {
    h += '<div class="note err">在 Safari 分頁裡開不了通知。請用下方步驟加到主畫面，' +
      '再從主畫面的圖示打開。</div>' +
      '<ol class="steps"><li>點 Safari 下方正中間的「分享」鈕</li>' +
      '<li>往下捲，選「加入主畫面」</li><li>回到主畫面，從那個圖示打開</li></ol>';
  }
  h += '<div id="enNote"></div></div>';

  h += '<div class="card">' +
    swRow('swNotice', '新提醒', '回覆、評分、系統提醒等', me.notifyNotice) +
    swRow('swPm', '新私訊', '有人傳私訊給你', me.notifyPm) +
    swRow('swSign', '自動簽到',
      me.autoSign ? '由伺服器代簽，簽完推結果給你' : '沒開啟時只在下面的時間提醒你',
      me.autoSign) +
    '<div id="remindWrap"' + (me.autoSign ? ' hidden' : '') + '>' +
    '<label for="remindAt">每天幾點提醒我簽到</label>' +
    '<input id="remindAt" type="time" value="' + esc(me.signReminderAt) + '"></div>' +
    '</div>';

  h += '<button class="b ghost" id="pollBtn">立刻檢查一次</button>';
  h += '<details><summary>診斷資訊</summary><div class="card"><div id="checks"></div>' +
    '<div id="log"></div></div></details>';
  main.innerHTML = h;

  $('checks').innerHTML =
    diagRow(isStandalone ? 'ok' : (isIOS ? 'bad' : 'warn'), '已加到主畫面',
      isStandalone ? '是' : '否') +
    diagRow(('serviceWorker' in navigator) && ('PushManager' in window) ? 'ok' : 'bad',
      '瀏覽器支援', ('PushManager' in window) ? 'Web Push ✓' : '不支援') +
    diagRow(window.isSecureContext ? 'ok' : 'bad', '安全連線', location.host);
  if (logLines.length) $('log').textContent = logLines.join('\n');

  const en = $('enBtn');
  if (en) en.onclick = enableNotifications;
  const tb = $('testBtn');
  if (tb) tb.onclick = async () => {
    tb.disabled = true;
    try {
      const out = await api('/api/test-push', { method: 'POST' });
      log('測試推播：' + JSON.stringify(out));
      log('沒跳出來的話把 App 切到背景再試 —— 前景時 iOS 常常不顯示橫幅。');
    } catch (e) { log('測試失敗：' + e.message); }
    finally { tb.disabled = false; }
  };

  $('swNotice').onchange = (e) => saveSettings({ notifyNotice: e.target.checked });
  $('swPm').onchange = (e) => saveSettings({ notifyPm: e.target.checked });
  $('swSign').onchange = async (e) => {
    await saveSettings({ autoSign: e.target.checked });
    viewSettings();
  };
  $('remindAt').onchange = (e) => saveSettings({ signReminderAt: e.target.value });
  $('pollBtn').onclick = async () => {
    $('pollBtn').disabled = true;
    $('pollBtn').textContent = '檢查中…';
    try { me = await api('/api/poll-now', { method: 'POST' }); renderBadges(); log('已檢查一次'); }
    catch (e) { log('檢查失敗：' + e.message); }
    finally { $('pollBtn').disabled = false; $('pollBtn').textContent = '立刻檢查一次'; }
  };
}

function swRow(id, name, desc, on) {
  return '<div class="srow"><div class="k"><b>' + esc(name) + '</b><small>' +
    esc(desc) + '</small></div><div class="sw"><input type="checkbox" id="' + id +
    '"' + (on ? ' checked' : '') + '><span></span></div></div>';
}
function diagRow(s, n, d) {
  return '<div class="srow"><div class="dot ' + s + '"></div><div class="k"><b>' +
    esc(n) + '</b><small>' + esc(d) + '</small></div></div>';
}

async function saveSettings(patch) {
  try { me = await api('/api/settings', { method: 'POST', body: JSON.stringify(patch) }); }
  catch (e) { log('設定沒存成功：' + e.message); }
}

function urlBase64ToUint8Array(base64) {
  const padded = (base64 + '='.repeat((4 - base64.length % 4) % 4))
    .replace(/-/g, '+').replace(/_/g, '/');
  return Uint8Array.from([...atob(padded)].map((c) => c.charCodeAt(0)));
}

async function enableNotifications() {
  const btn = $('enBtn');
  btn.disabled = true;
  try {
    // 權限一定要在使用者手勢裡要，自動跑會被瀏覽器擋掉
    const perm = await Notification.requestPermission();
    log('權限結果：' + perm);
    if (perm !== 'granted') {
      $('enNote').innerHTML = '<div class="note err">' +
        (perm === 'denied' ? '已被拒絕。要到「設定 → 通知 → GameMale」裡重新打開。'
                           : '沒授權就收不到通知。') + '</div>';
      return;
    }
    let sub = await registration.pushManager.getSubscription();
    if (!sub) {
      sub = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidKey),
      });
    }
    me = await api('/api/subscribe', { method: 'POST', body: JSON.stringify(sub.toJSON()) });
    log('已綁定這台裝置');
    viewSettings();
  } catch (e) {
    $('enNote').innerHTML = '<div class="note err">' + esc(e.message) + '</div>';
  } finally { btn.disabled = false; }
}

// ── 登入 ─────────────────────────────────────────────────────
let loginId = null;

function renderLogin() {
  $('nav').hidden = true;
  setTitle('登入 GameMale', false);
  main.innerHTML =
    (isIOS && !isStandalone
      ? '<div class="card"><b>建議先加到主畫面</b>' +
        '<div style="font-size:14px;color:var(--dim);margin-top:4px">' +
        'iOS 只讓主畫面 App 收推播，在 Safari 分頁裡看得到內容但不會有通知。</div>' +
        '<ol class="steps"><li>點下方正中間的「分享」鈕</li>' +
        '<li>往下捲，選「加入主畫面」</li><li>從主畫面的圖示打開</li></ol></div>'
      : '') +
    '<div class="card">' +
    '<label for="u">論壇帳號</label>' +
    '<input id="u" type="text" autocomplete="username" autocapitalize="none" spellcheck="false">' +
    '<label for="p">密碼</label>' +
    '<input id="p" type="password" autocomplete="current-password">' +
    '<div id="qWrap" hidden><label for="q">安全提問</label><select id="q"></select>' +
    '<label for="qa">答案</label><input id="qa" type="text" autocapitalize="none"></div>' +
    '<div id="capWrap" hidden><label for="cap">驗證碼</label>' +
    '<div class="captcha"><img id="capImg" alt="驗證碼"><input id="cap" type="text" ' +
    'autocapitalize="none" spellcheck="false"></div></div>' +
    '<button class="b" id="loginBtn">登入</button>' +
    '<div id="loginErr"></div>' +
    '<div style="font-size:12px;color:var(--dim);margin-top:14px">' +
    '密碼只會轉送到論壇換取登入狀態，<b>不會存在伺服器上</b>。' +
    '伺服器只保管登入後的 session（加密存放），用來替你查有沒有新通知。' +
    '你在論壇按登出，它就立刻失效。</div></div>';

  $('loginBtn').onclick = doLogin;
  beginLogin().catch((e) => log('取登入表單失敗：' + e.message));
}

async function beginLogin() {
  const info = await api('/api/login/begin', { method: 'POST' });
  loginId = info.id;
  $('capWrap').hidden = !info.needSeccode;
  if (info.captcha) $('capImg').src = info.captcha;
  const qs = info.questions || [];
  $('qWrap').hidden = qs.length === 0;
  $('q').innerHTML = qs.map((q) =>
    '<option value="' + esc(q.id) + '">' + esc(q.name) + '</option>').join('');
}

async function doLogin() {
  const btn = $('loginBtn');
  btn.disabled = true;
  $('loginErr').innerHTML = '';
  try {
    if (!loginId) await beginLogin();
    if (!$('capWrap').hidden && !$('cap').value.trim()) throw new Error('請輸入驗證碼');
    const out = await api('/api/login/finish', {
      method: 'POST',
      body: JSON.stringify({
        id: loginId,
        username: $('u').value,
        password: $('p').value,
        questionid: $('qWrap').hidden ? '0' : $('q').value,
        answer: $('qa') ? $('qa').value : '',
        seccode: $('cap').value,
      }),
    });
    loginId = null;
    me = out.account;
    renderBadges();
    go('#/');
    route();
  } catch (e) {
    $('loginErr').innerHTML = '<div class="note err">' + esc(e.message) + '</div>';
    // 驗證碼與 loginhash 都是一次性的，失敗後一定要重新取一份
    loginId = null;
    try { await beginLogin(); $('cap').value = ''; } catch (_) {}
  } finally { btn.disabled = false; }
}

// ── 啟動 ─────────────────────────────────────────────────────
async function boot() {
  if ('serviceWorker' in navigator && window.isSecureContext) {
    try {
      registration = await navigator.serviceWorker.register('/sw.js');
      await navigator.serviceWorker.ready;
      log('service worker 就緒');
    } catch (e) { log('service worker 註冊失敗：' + e); }
  }
  try {
    const cfg = await api('/api/config');
    vapidKey = cfg.vapidPublicKey;
  } catch (e) { log('拿不到伺服器設定：' + e.message); }

  try {
    me = await api('/api/me');
    renderBadges();
  } catch (_) { me = null; }

  route();
}

// 從通知點進來時會帶 hash，回到前景順便更新紅點
document.addEventListener('visibilitychange', async () => {
  if (document.visibilityState === 'visible' && me) {
    try { me = await api('/api/me'); renderBadges(); } catch (_) {}
  }
});

boot();
