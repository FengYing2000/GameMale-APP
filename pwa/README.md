# GameMale PWA — 第一階段：打通推播

把 GameMale 改寫成「加到主畫面」的網頁 App。原本的 Flutter 版留在上層資料夾，
兩者並存，這邊不會動到它。

## 為什麼要做這個

側載的 IPA 有兩個治不好的毛病：

| | 側載 IPA | PWA |
|---|---|---|
| 推播 | 只能本地通知，App 被強制關閉就完全停掉 | 真推播，關掉也收得到 |
| 費用 | 要真推播得付 Apple 開發者帳號一年 99 美金 | 免費，VAPID 金鑰自己產 |
| 有效期 | **7 天到期，要重簽重裝** | 不會過期 |
| 安裝 | 要 AltStore 之類的側載工具 | Safari 點「加入主畫面」 |

iOS 16.4 起支援 Web Push，而且**不需要付費開發者帳號**——這是原生側載版
拿不到的東西。

## 目前的進度

**推播已經在實機上驗證通過**（iOS 18.7，加到主畫面後收得到）。
論壇功能還沒接上去，但資料層已經共用了。

這個順序是刻意的：整個計畫的成敗全押在「Web Push 在你的 iPhone 上真的會跳
通知」，而那是唯一沒辦法從程式碼確定的事。先花一天證明它會動，比先寫兩星期
的論壇功能再發現推播不通划算得多。

已完成：

- **RFC 8291 訊息加密**（`server/lib/webpush.dart`）——
  pub.dev 上沒有任何 Dart 實作，照規格自己寫的。
  每個中間值都用 RFC 官方測試向量驗證過。
- **RFC 8292 VAPID 授權**（`server/lib/vapid.dart`）——金鑰產生、JWT 簽章。
- **推播發送**（`server/lib/push_client.dart`）——含訂閱失效自動清除。
- **診斷用的 PWA**（`web/`）——會逐項顯示哪個前置條件沒過。
- **共用論壇資料層**——把原本 `lib/api/` 那 6400 行抽成純 Dart 套件
  `packages/gm_api`，Flutter App 與這個後端**用同一份程式碼**解析論壇。
  那些選擇器和端點是十幾輪踩出來的，用別的語言重寫一次等於把雷全部再踩一遍。

還沒做：論壇登入、伺服器輪詢、真正的 App 介面。

## 共用資料層是怎麼共用的

`packages/gm_api` 刻意**不依賴 Flutter**，代價是它拿不到 `path_provider`
與 `rootBundle`，所以那兩件事改成由平台端注入：

| | Flutter App | PWA 後端 |
|---|---|---|
| 注入的地方 | `lib/platform_bindings.dart` | `pwa/server/lib/forum.dart` |
| cookie 存哪 | `PersistCookieJar`（app 支援目錄） | `PersistCookieJar`（`/data`） |
| 簡繁對照表 | `rootBundle.loadString` | 從 `/srv/assets` 讀檔 |

**任何進入點都要先呼叫一次注入函式**——App 是 `main()` 和背景任務（背景是
另一個 isolate，`main()` 的注入不會跟過去），測試則在 `setUpAll` 裡呼叫。
`pwa/server/test/shared_parser_test.dart` 就是在守這件事：哪天有人在
`gm_api` 裡不小心 import 了 Flutter 的東西，那支測試會第一個編不過。

## 跑起來

### 本機

```bash
cd server
dart pub get
dart run bin/vapid_keygen.dart          # 產金鑰，存起來

VAPID_PRIVATE_KEY=剛剛那串 dart run bin/server.dart
```

開 <http://localhost:8080>。**本機只能測到訂閱為止**——localhost 算安全來源，
service worker 註冊得起來，但手機要連得到才能收推播，所以真正的驗證要部署上去。

### 部署到香港 VPS（已經架好了）

目前跑在 <https://160.236.111.8.sslip.io>，Dockge 裡的 stack 名稱 `gamemale-pwa`
（`/opt/stacks/gamemale-pwa`）。

```bash
cp .env.example .env       # 填入 VAPID_PRIVATE_KEY
docker compose up -d --build
```

容器不綁主機埠，跟站上其他服務一樣加入共用的 `web` 網路，由 Caddy 用容器名代理。
Caddy 那邊加的區塊**刻意不 import common**：

```
160.236.111.8.sslip.io {
    encode zstd gzip
    reverse_proxy gm-push:8080
}
```

`common` 帶的是 Cloudflare Origin 憑證，只有 CF 信任得過；這站是 DNS 直連不走
Cloudflare，所以不寫 `tls`，讓 Caddy 自己跟 Let's Encrypt 要一張公開受信任的憑證
——**iOS 一定要憑證受信任才肯註冊 service worker，自簽的不行**。

`sslip.io` 是把 IP 編進主機名的公用 DNS（`160.236.111.8.sslip.io` 就解析到
`160.236.111.8`），所以完全不用動 Cloudflare 的 DNS 記錄。要換成正式子網域，
把主機名改掉、DNS 指過來（**灰雲，不能開橘雲代理**）即可。

改完 Caddyfile 要 `docker restart caddy`——設定裡 `admin off`，沒辦法熱重載，
重啟會讓站上所有服務中斷兩三秒。

## 在 iPhone 上驗證

1. Safari 開 `https://gm.xingkong.tw`
2. 分享 → **加入主畫面**（這步不能跳過，iOS 只讓主畫面 App 收推播）
3. 從主畫面的圖示打開，按「開啟通知」→ 允許
4. 按「送一則測試通知」

診斷卡片會逐項標示綠燈或紅燈，哪一項沒過一目了然。

**在 Windows 本機測不到真的推播**：Dart 在 Windows 上找不到系統根憑證，
連 push service 會 `CERTIFICATE_VERIFY_FAILED`。Docker 映像有裝
`ca-certificates`，部署上去就正常，本機只能測到訂閱為止。

**測不出來時先看這幾點：**

- 通知沒跳出來 → 先把 App 切到背景。前景時 iOS 常常不顯示橫幅，這是正常的。
- 「已加到主畫面」是紅的 → 你還在 Safari 分頁裡，push 一定不會通。
- 要 iOS 16.4 以上。

## 幾個踩過的雷

- **`package:cryptography` 在伺服器端不能用**：它的 `DartEcdh.sharedSecretKey`
  是 `throw UnimplementedError()` 的空殼，P-256 全丟給瀏覽器或原生外掛做。
  改用 `pointycastle`。
- **pointycastle 的 `decodePoint` 不驗曲線**：隨便 65 個位元組它都收。
  RFC 8291 的安全性考量寫的是 MUST 要驗——不驗會構成 invalid curve attack，
  攻擊者反覆送特製公鑰就能從 ECDH 結果反推私鑰。`isOnCurve()` 補上了。
- **表頭是 86 bytes，不是 3 的倍數**：所以
  `b64u(表頭) + b64u(密文) ≠ b64u(表頭 + 密文)`，比對要比位元組。
- **iOS 收到推播就一定要顯示通知**：不能拿 push 靜默同步紅點，
  Safari 發現你收了不顯示會直接收回通知權限。
- **VAPID 金鑰換掉 = 所有訂閱失效**，每個使用者都要重新授權。產一次就存好。

## 測試

```bash
cd server && dart test        # 46 項，不需要網路
```

涵蓋 RFC 8291 官方測試向量（逐個中間值）、VAPID 簽章與驗章、
訂閱資料的格式與長度驗證、曲線點驗證。
