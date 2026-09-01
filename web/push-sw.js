// GameMale 網頁版的推播 service worker。
//
// 跟 Flutter 自己產的 flutter_service_worker.js 是兩支不同的東西：
// 那支管離線快取，這支只管推播。分開註冊，互不干擾。

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  // iOS 規定收到推播就**一定要**顯示通知。收了卻不顯示，
  // Safari 會直接把通知權限收回去，所以這裡不能有靜默分支。
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }

  event.waitUntil(
    self.registration.showNotification(data.title || 'GameMale', {
      body: data.body || '',
      icon: 'icons/Icon-180.png',
      badge: 'icons/Icon-180.png',
      tag: data.tag || 'gm',
      renotify: true,
      data: { url: data.url || '/' },
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || './';

  event.waitUntil(
    (async () => {
      const list = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
      for (const c of list) {
        if ('focus' in c) {
          try {
            await c.navigate(url);
          } catch (_) {
            // 跨來源或已卸載的分頁 navigate 會丟例外，聚焦就好
          }
          return c.focus();
        }
      }
      return self.clients.openWindow(url);
    })()
  );
});
