# GameMale iOS

給 [www.gamemale.com](https://www.gamemale.com/)（Discuz! X）用的 iOS 客戶端。
Flutter 原生 UI，資料直接讀論壇手機版頁面 —— 不經過任何第三方伺服器。

---

## 為什麼是解析 HTML，不是打 API

先探測過了：這站的官方 Discuz 手機 API **是關掉的**。

```
GET /api/mobile/index.php?version=4&module=forumindex  →  200，回應長度 0
```

PHP 有執行（會回 `Set-Cookie`），但所有 JSON 模組都回空字串，只有 `mynotelist`
漏出老舊的 WAP 模板。所以走的是第二條路：帶 `mobile=2` 取手機版模板
（`xinrui_iuni_mobile/touch`），再用 `package:html` 解析。

手機版模板只有 37 KB（桌面版 187 KB），節點結構乾淨，解析成本比想像中低很多。

---

## 架構

```
lib/
  api/
    models.dart    所有資料型別（空安全，UI 端不會拿到 dynamic）
    http.dart      dio + PersistCookieJar，cookie 落地所以冷啟動免重登
    parse.dart     DOM 工具 + 內容淨化（去 script、還原延遲載入圖、網址絕對化）
    discuz.dart    所有端點；純解析函式獨立匯出，方便測試
  store/session.dart
  theme.dart       品牌色沿用論壇的簽到綠，Material 3 深淺色自動
  ui/
    widgets/       PostBody ThreadTile Avatar StateBox PagerBar ImageViewer
    pages/         17 個頁面
test/
  parse_test.dart    真實頁面樣本驗證解析器（70 項）
  render_test.dart   真實帖子 HTML 丟進 PostBody 確認畫得出來（12 項）
  pages_test.dart    每一頁 pump 起來 + 離線行為（20 項）
  live_test.dart     對真實論壇的端對端測試（9 項，需要 cookie）
tool/
  fetch_fixtures.dart  重抓樣本
  build-ipa.sh         在任一台 Mac 上產出 IPA（不需要 GitHub 或任何 CI）
  make-icon.mjs        產生 App 圖示（純 Node，不依賴影像套件）
```

### 幾個關鍵決定

**登入狀態不靠讀 cookie 判斷**，而是看頁面裡有沒有登出連結。Discuz 的
cookie 有沒有效只有伺服器知道，去猜只會出錯。

**驗證碼圖片走 `Api.getBytes()` 拿 bytes 再用 `Image.memory`**，不能直接丟
`Image.network` —— 那條請求不會帶上 session cookie，拿到的驗證碼跟伺服器記的對不起來。

**`package:html` 的選擇器引擎不支援 `:first-of-type` / `:last-child`**，
子版塊那類查詢改成手動走訪子節點（`firstChildTag`）。

**spoiler 折疊區塊**在淨化階段標成 `data-spoiler`，再由 `PostBody` 的
`customWidgetBuilder` 畫成 `ExpansionTile`。

---

## 功能

| | |
|---|---|
| 瀏覽 | 板塊列表、主題列表（全部／最新／熱門／精華、主題分類、子版塊）、帖子內頁、分頁 |
| 互動 | 回覆、引用回覆、發新主題（含主題分類）、收藏／取消收藏 |
| 帳號 | 帳密登入（含圖形驗證碼、安全提問）、登出、個人中心、他人資料 |
| 訊息 | 系統通知（我的帖子／坛友互动／系统通知／管理）、私訊列表與對話 |
| 其他 | 每日簽到（k_misign，含等級經驗條）、導讀、搜尋、我的收藏／主題／回覆 |
| 體驗 | 深／淺色自動、下拉重新整理、圖片點擊全螢幕可縮放、BBCode 快捷列、五分頁各自保有導航堆疊 |

---

## 開發

Flutter SDK 3.47.1 以上。

```bash
flutter pub get
flutter analyze
flutter test              # 102 項離線測試
```

> **Windows 上必須把專案放在純 ASCII 路徑**（例如 `C:\src\gamemale`）。
> 路徑含中文時 Dart 分析伺服器會因為 LSP 訊息長度用字元數算、實際傳輸用位元組數
> 而崩潰（`FormatException: Unexpected end of input`）。這是工具鏈的限制，不是設定問題。

### 論壇改版時

```bash
$env:GM_COOKIE = "TVj0_2132_auth=...; TVj0_2132_saltkey=..."
$env:GM_UID = "733814"
dart run tool/fetch_fixtures.dart
flutter test
```

壞掉的選擇器會直接被指出來，不用在手機上瞎猜哪裡白畫面。

### 端對端測試（會發真實請求）

```bash
flutter test test/live_test.dart --dart-define="GM_COOKIE=$env:GM_COOKIE"
```

沒帶 cookie 就整組略過，CI 不會因此失敗。

---

## 產出 IPA

編 iOS 一定要 macOS，這點沒有例外 —— 換框架、裝外掛都繞不過去，因為最後一步要連結
iOS SDK、跑 `actool` 編素材，那些二進位檔只在 macOS 上發行。

但**不一定要用 GitHub**，兩條路都能產出未簽名 IPA 供你自簽側載。

### 方式一：自己找一台 Mac（不需要 GitHub）

租的雲端 Mac、借來的 Mac 都行。把專案傳過去，跑：

```bash
chmod +x tool/build-ipa.sh
./tool/build-ipa.sh
```

腳本會檢查 Xcode、必要時自動裝 Flutter、跑分析與測試、產出 `GameMale.ipa`。

> 免費 Apple ID 憑證雖然 7 天到期，但**重簽用的是同一個 IPA**，不必重編。
> 所以只有改程式碼時才需要跑建置。

### 方式二：GitHub Actions

推上 `main` 就會自動建置，也可以在 Actions 頁手動點 **Run workflow**。
跑完在該次 run 的 Artifacts 下載 `GameMale-unsigned-ipa`。

> **私有 repo 要注意**：macOS runner 的用量以 **10 倍**計。免費額度 2000 分鐘
> ≈ 200 分鐘 macOS，一次建置約 8–12 分鐘，所以大約每月 16–24 次。
> 公開 repo 則完全免費不限量。

### 側載到手機

下載的 `GameMale.ipa` 是未簽名的，三種方式擇一：

- **Sideloadly**（Windows 最省事）— 接上 iPhone、拖入 IPA、填 Apple ID，按 Start
- **AltStore / SideStore** — 可自動續簽，免費帳號 7 天到期前會自己重簽
- **ESign / TrollStore** — 手機上直接簽，不用電腦

免費 Apple ID 的憑證 7 天到期，到期重簽即可，資料不會掉。

---

## 目前沒做的部分

- **發文上傳圖片／附件** — Discuz 的 `swfupload` 是 multipart 端點，沒有實機沒辦法驗證，
  與其塞一個沒測過的功能不如先不做。目前發文可以用 `[img]網址[/img]`
- **樓中樓回覆**（`dxksst` 外掛）— 只顯示主樓層，樓中樓內容不展開
- **勳章商城／道具商城** — 已經有 Tampermonkey 腳本在做這兩件事
- **投票、評分、積分明細**
- **推播通知** — 需要自架推播伺服器與 APNs 憑證，自簽 App 拿不到

## 隱私

帳號密碼只會送到 `www.gamemale.com`，cookie 存在 App 自己的沙箱裡，
不連任何第三方服務。

`Info.plist` 有開 `NSAllowsArbitraryLoads` —— 帖子裡的圖片來自使用者貼的任意外站網址，
沒辦法列舉白名單。這是側載自用的 App，不上架，所以這樣取捨。
