# GameMale 網頁版後端

把 Flutter 網頁版（`flutter build web`）掛在自己的網域上，讓 iPhone 可以
「加到主畫面」當成 App 用 —— 不必側載、不必每 7 天重簽。

線上是 <https://852111.xyz>（香港 VPS，Dockge + Caddy）。

## 它只做三件事

| | 為什麼非要有 |
|---|---|
| **掛靜態檔** | `flutter build web` 的產出。入口檔送 `no-cache`，`canvaskit/`、`assets/`、`icons/` 給長快取 |
| **`/gm` 論壇轉發** | 瀏覽器不准跨網域打論壇（論壇一個 CORS 標頭都沒送）。同源之後登入 cookie 由瀏覽器自己保管 |
| **`/gmimg` 圖片代理** | 帖子裡的圖常放在沒送 CORS 的第三方圖床，而 App 是把圖讀進 canvas 的，跨網域讀像素會被擋掉 |

**伺服器上沒有任何帳號資料。** 不存 cookie、不存密碼、沒有資料卷、
沒有任何機密環境變數。登入狀態完全在瀏覽器裡，跟你直接開論壇網站一樣。

> 曾經有一套推播通知（自寫的 RFC 8291／8292 Web Push＋每 5 分鐘輪詢論壇）。
> 那需要在伺服器上保存加密後的論壇 cookie 才能代你查未讀。實際用下來
> 價值不足以抵銷那個代價，整套已經移除 —— 這也是上面那行「沒有任何帳號
> 資料」現在成立的原因。

## 跑起來

### 本機

```bash
flutter build web --release --pwa-strategy=none   # 先產出網頁版
cd pwa/server && dart run bin/server.dart
```

開 <http://localhost:8080>。沒有要設的環境變數。

`--pwa-strategy=none` 是刻意的：Flutter 產的 service worker 會把舊版
程式碼快取住，部署完看到的還是舊的。

### 部署到香港 VPS

伺服器上的目錄結構跟這個 repo 一模一樣（`/opt/stacks/gamemale-pwa/`），
所以不會有「本機一套、線上一套」的問題。

```bash
flutter build web --release --pwa-strategy=none
# 把 build/web、pwa/、packages/gm_api、docker-compose.yml 送上去，然後：
cd /opt/stacks/gamemale-pwa && docker compose build && docker compose up -d
```

⚠️ `build/web` 要**先清空再解壓**。tar 是疊加的，刪掉的檔案會留在伺服器上
繼續被服務（`push-sw.js` 就這樣多活了一輪）。

容器不綁主機埠，加入共用的 `web` 網路，由 Caddy 用容器名代理。

## 加到主畫面

Safari 開 <https://852111.xyz> → 右下角「⋯」→ 分享 → 加入主畫面。
之後從圖示打開就沒有網址列、全螢幕、有自己的圖示。
首頁上有一張常駐橫幅會講同樣的步驟。

## 幾個踩過的雷

- **轉發一定要用原始 query 字串**，不能用 `queryParameters` 重建。
  那是 Map，存不下重複的 key，而論壇有些網址就是會帶
  `&mobile=no&mobile=2` 兩個 `mobile`。只留最後一個的話論壇回不同模板，
  解析器什麼都抓不到（記錄廣場整頁空白就是這樣來的）。
- **`Set-Cookie` 的 Domain 要拔掉、Path 要設成 `/`**。留著
  `.gamemale.com` 瀏覽器會整條丟掉。
- **轉址不能跳出同源**。論壇的圖片端點會 302 到 `img.gamemale.com`，
  那個網域沒送 CORS，跳出去之後 App 讀不到像素（用瀏覽器直接開卻沒事，
  因為那是導覽不是讀像素）。所以連轉址目標也接回 `/gmimg`。
- **`/gmimg` 不能只開白名單**。第三方圖床幾乎都沒送 CORS，主機必須全放。
  安全靠另外兩道：**回應不是 `image/*` 就不轉**，以及**擋掉會打到內網的
  位址**（`isPrivateHost`：迴環、私有段、CGNAT、link-local ——
  `169.254.169.254` 那類雲端 metadata 是最典型的 SSRF 目標）。
  刻意不做「先 DNS 解析再比對」：解析結果跟等一下真正連線時未必相同
  （DNS rebinding），擋不住卻會拖慢每一張圖。
- **靜態檔一定要送快取標頭**。`main.dart.js` 檔名固定、不帶內容雜湊，
  不送標頭的話瀏覽器自己決定重用多久 —— 結果就是每次部署完使用者手上
  還是舊程式碼，修好的東西看起來像沒修好（這件事實際害我們來回除錯好幾輪）。

## 測試

```bash
cd pwa/server && dart test        # 28 項，不需要網路
```

`dart analyze` 與 `dart test` 都跑在 Docker build 裡，沒過就不會產出映像。
