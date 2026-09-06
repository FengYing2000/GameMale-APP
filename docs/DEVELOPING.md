# 開發筆記

這份文件是給要動這個專案的人看的：架構、技術取捨，以及十幾輪實作累積下來的雷。
**使用者請看 [README](../README.md)。**

繁簡對照與更多細節見 [pwa/README.md](../pwa/README.md)（網頁版後端）。

---

## 技術取捨

### 為什麼是解析 HTML，不是打 API

探測結果很明確 —— 這站的官方 Discuz 手機 API **已被關閉**：

```http
GET /api/mobile/index.php?version=4&module=forumindex
→ 200 OK，回應長度 0
```

PHP 確實執行了（會回 `Set-Cookie`），但所有 JSON 模組都回空字串，
只有 `mynotelist` 漏出老舊的 WAP 模板。

所以走第二條路：帶 `mobile=2` 取手機版模板（`xinrui_iuni_mobile/touch`），
再用 `package:html` 解析。手機版模板只有 **37 KB**（桌面版 187 KB），節點結構乾淨。

### 幾個關鍵決定

| 決定 | 原因 |
|---|---|
| **登入狀態只認登出連結** | 訪客版底部導覽也有 `mycenter=1` 的「我的」，拿它當證據會把訪客判成已登入 |
| **判定訪客要看到登入入口** | `inajax=1` 的浮層片段兩種標記都沒有，用「缺少登出連結」反推會害使用者一點評分就被登出 |
| **需要登入要看 `#loginform`** | 訪客瀏覽公開板塊時頁尾一樣有登入連結，用它會把每個板塊都擋掉 |
| **驗證碼走 `getBytes` + `Image.memory`** | `Image.network` 不會帶 session cookie，拿到的驗證碼跟伺服器記的對不起來 |
| **發文走桌面端點** | 論壇處理邏輯相同，但外掛（勳章積分）掛在桌面流程上 |
| **桌面模板要明寫 `mobile=no`** | 只是不帶 `mobile=2` 沒用 —— Discuz 會依 iPhone UA 自動轉手機版 |
| **POST 的轉址要自己跟** | Dart 的 HttpClient 只自動跟隨 GET/HEAD，POST 收到 302 會拿到空 body |
| **積分變化要用 ID 定位** | `creditnotice` cookie 第 0 格是總積分，第 1～8 格照積分 ID 擺；照名稱表順序數會整串位移一格 |
| **已回帖用 `authorid` 反問** | 論壇沒有現成清單，但帶 `authorid=<自己>` 開帖時沒發言過會回「未定义操作」（約 4.7 KB） |
| **收藏狀態要自己記** | 帖子頁的收藏連結永遠寫著「收藏本帖」，按下去才知道收過沒有，所以把收藏清單抓回本機比對 |
| **勳章 tip 照結構拆** | 等級和名字之間沒有空白，正則會黏成「Max黑暗之魂系列」；`<b>` 是等級、`<h4>` 其餘是名字 |
| **「沒有登出連結」不等於登出** | 論壇偶爾回一頁兩種標記都沒有的東西，照舊邏輯會把使用者標成憑證失效、半夜推一則「請重新登入」；要兩邊都拿正面證據，判讀不出來就當這輪沒查到 |
| **深色底的灰字要明講顏色** | 回 `null` 等於不覆寫，元素上的 `color="#333"` 還是會生效 |
| **論壇頁面用內建瀏覽器** | 丟給系統瀏覽器那邊沒有登入狀態，所以把 App 的 cookie 灌進 WebView |
| **論壇內容一律保留原文** | 轉過的標題跟網頁版對不起來，所以簡繁轉換改成帖子頁上逐篇按 |
| **取消收藏是兩步驟** | 先 GET 拿確認表單（formhash 跟頁面上的不同），再 POST `deletesubmit=true` 才真的刪 |
| **ajax 回應要抽訊息** | 整包只是一段 `<script>`，直接當文字會把 JavaScript 唸出來 |
| **圖片有四種來源** | 一般網址、`data:` 內嵌、jsdelivr 的 `.svg` emoji、第三方圖床；各自要不同的處理，否則整片「載入失敗」 |
| **CanvasKit 不用系統字體** | 網頁版遇到沒載入的字會即時去 gstatic 抓 Noto，抓回來之前整片方格打叉；中文字體要自己內建並在 `runApp` 前 await |
| **圖片要照顯示尺寸解碼** | 頭像原圖 200px 以上、列表只畫 40px，照原尺寸解碼等於每張多花十幾倍記憶體，捲動時還要把過大的貼圖全傳給 GPU |
| **Flutter 不解 SVG** | 論壇有人插 noto-emoji 的 `.svg`，內建解碼器畫不出來（原生版也一樣，跟 CORS 無關）；換成同一個 repo 的 `png/128/` 就好，不必為表情拉一個 SVG 套件 |
| **圖片與連結要分開處理** | 網頁版靠改寫網址走代理，而 `absolute()` 同時用在 `<img src>` 和 `<a href>` 上。把連結也丟進圖片代理，道具、收藏那些端點就會 404——所以圖片改用 `absoluteImage()` |
| **附件也有三種長相** | 帖尾的 `dl.tattl`、內文中間的 `span#attach_N`、「更多圖片」的 `dl.tattl.attm`（要排除） |
| **附件內容自己解碼** | 伺服器送 `octet-stream` 又不帶 charset，瀏覽器在繁中系統會猜成 Big5，UTF-8 檔就變亂碼 |
| **分頁要記住請求的頁數** | 有些列表只給「上一頁／下一頁」，照 DOM 算會永遠停在第 1 頁，還把下一頁的 `page=3` 當成總頁數 |
| **刪除都是兩步驟** | 先 GET 拿確認表單（formhash 跟頁面上的不同），再 POST 才真的刪；抽成 `confirmAndSubmit` 共用 |
| **頁首的私訊數會被自己清掉** | 使用者瞄一眼訊息列表，論壇就把頁首那個數字歸零，但對話本身還是未讀——紅點只看頁首就會整批漏掉，要用每則對話自己的未讀數 |
| **系統文字才跟著介面語言** | 版塊名、積分名、論壇提示用 `sys()` 轉；帖子標題與內文一律原文，要看繁體按帖子頁的翻譯 |
| **附件的數字 id 不在下載連結裡** | 已購買的連結帶的是 base64 的 `aid`，數字版要從 `span#attach_N` 或購買紀錄連結拿 |
| **群組是另一套頁面** | `group-<fid>-1.html` 只有桌面模板，用 `/f/<fid>` 進去會顯示「沒有主題」 |
| **簡繁轉換自訂規則** | OpenCC 的第一候選常常不合語境（`签到`→`籤到`、`295 里`→`295 裡`） |

---

---

## 架構

```
lib/
├── api/
│   ├── models.dart      所有資料型別（空安全，UI 拿不到 dynamic）
│   ├── http.dart        dio + PersistCookieJar，cookie 落地免重登
│   ├── parse.dart       DOM 工具、內容淨化、登入狀態判定
│   ├── discuz.dart      主要端點；純解析函式獨立匯出方便測試
│   ├── search.dart      五種搜尋分類
│   ├── space.dart       個人空間七個子頁
│   ├── smilies.dart     表情清單（讀論壇自己的快取檔）
│   └── register.dart    註冊問答
├── i18n/
│   ├── s2t.dart         簡→繁（台灣用語）
│   └── ui.dart          介面繁→簡
├── store/               session（登入狀態）· settings（語言／主題／強調色／流量）· history（回帖紀錄）
└── ui/
    ├── widgets/         PostBody · ComposerToolbar · Avatar · StateBox · StickyPager …
    └── pages/           淘帖、記錄、簽到…等頁面

tool/
├── zh_rules.py          簡繁轉換的人工規則 ← 要調整用字改這裡
├── build_zh_table.py    產生 assets/s2t.json
├── fetch_fixtures.dart  重抓測試樣本
├── make-icon.mjs        產生 App 圖示（純 Node）
└── build-ipa.sh         在任一台 Mac 上產 IPA
```

---

## 測試策略

論壇隨時可能改版，選擇器一壞畫面就空白。所以測試不是形式，而是**用真實頁面驗證解析器**。

| 檔案 | 內容 | 數量 |
|---|---|---|
| `parse_test.dart` | 用真實抓下來的頁面驗證每個選擇器 | 227 |
| `pages_test.dart` | 每頁 pump 起來 + 離線行為 | 33 |
| `s2t_test.dart` | 簡繁轉換的每一類判斷 | 21 |
| `render_test.dart` | 真實帖子 HTML 丟進 PostBody 確認畫得出來 | 12 |
| `live_test.dart` | 對真實論壇的端對端（需 cookie，CI 自動略過） | 51 |

```bash
flutter test                        # 293 項離線測試
flutter analyze                     # 零問題
```

**論壇改版時：**

```powershell
$env:GM_COOKIE = "TVj0_2132_auth=...; TVj0_2132_saltkey=..."
$env:GM_UID = "677863"
dart run tool/fetch_fixtures.dart   # 重抓樣本
flutter test                        # 壞掉的選擇器會直接指名
```

---

## 開發

需要 Flutter SDK 3.47 以上。

```bash
flutter pub get
flutter analyze
flutter test
```

> [!IMPORTANT]
> **Windows 上必須把專案放在純 ASCII 路徑**（例如 `C:\src\gamemale`）。
> 路徑含中文時 Dart 分析伺服器會崩潰 —— LSP 訊息長度用字元數算、實際傳輸用位元組數，
> 中文百分比編碼後對不上。這是工具鏈限制，不是設定問題。

### 調整簡繁用字

不需要動程式碼，改 [`tool/zh_rules.py`](tool/zh_rules.py) 即可：

```python
EXCLUDE       # 完全不轉的字：里 台 范 谷 尸 姜 …
CHAR          # 一對多時選哪個：签→簽（不是籤）
DISAMBIGUATE  # 逐字會錯的詞：这里→這裡、头发→頭髮
TAIWAN        # 台灣用語：软件→軟體、鼠标→滑鼠、链接→連結
```

```bash
python tool/build_zh_table.py       # 重新產生 assets/s2t.json
flutter test test/s2t_test.dart     # 驗證
```

> 4012 個簡體字裡 3736 個是一對一（`国→國`），沒有判斷空間；
> 只有 276 個一對多的會轉錯，規則檔只管這些。

---

## 產出 IPA

編譯 iOS 一定要 macOS —— 換框架、裝外掛都繞不過去，因為最後一步要連結 iOS SDK、
跑 `actool` 編素材，那些二進位檔只在 macOS 上發行。

但**不一定要用 GitHub**。

### 方式一：任一台 Mac

```bash
chmod +x tool/build-ipa.sh
./tool/build-ipa.sh
```

腳本會檢查 Xcode、必要時自動裝 Flutter、跑分析與測試、產出 `GameMale.ipa`。

### 方式二：GitHub Actions

推上 `main` 自動建置，或在 Actions 頁手動觸發，完成後從 Artifacts 下載。

```bash
gh run download <run-id> -n GameMale-unsigned-ipa -D ./out
```

> [!NOTE]
> 私有 repo 的 macOS runner 用量以 **10 倍**計。免費額度 2000 分鐘 ≈ 200 分鐘 macOS，
> 一次建置約 5 分鐘，大約每月 40 次。公開 repo 免費不限量。

### 側載

產出的是**未簽名 IPA**，三種方式擇一：

| 工具 | 適用 | 特點 |
|---|---|---|
| **Sideloadly** | Windows | 接手機、拖入 IPA、填 Apple ID |
| **AltStore / SideStore** | 跨平台 | 可自動續簽，免費帳號到期前自動重簽 |
| **ESign / TrollStore** | 手機端 | 不用電腦 |

免費 Apple ID 憑證 7 天到期，**重簽用同一個 IPA 即可，不必重編**。

---

## 產出 APK（Android）

推上 `main` 會同時跑 `.github/workflows/android.yml`，在 **ubuntu** 上建置：

```bash
gh run download <run-id> -n GameMale-apk -D ./out
```

比 iOS 省事的地方：

| | iOS | Android |
|---|---|---|
| CI 分鐘數 | macOS，**10 倍**計 | ubuntu，**1 倍** |
| 安裝 | 未簽名 IPA，要側載工具重簽 | APK 直接裝 |
| 有效期 | 免費憑證 **7 天**到期要重簽 | **不會過期** |

APK 用 Flutter 自動產生的 debug 金鑰簽章 —— 側載裝得起來，但**不能上架 Google Play**。

---

## 網頁版

`flutter build web --wasm --release --pwa-strategy=none` 之後掛在自己的網域上。
後端與部署細節（論壇轉發、圖片代理、中文字體怎麼裁出來的）見
[pwa/README.md](../pwa/README.md)。

## 通知系統已移除

2026-09-04 移除。原生的背景輪詢＋本地通知、網頁版的自寫 Web Push（RFC 8291／8292）
＋伺服器輪詢，兩套都拿掉了。原因是送達時機由系統決定、不可控，而網頁版那套還得讓
伺服器保存論壇 cookie。實作仍在 git history 裡，要復原找得到。

---

## Cloudflare 擋在論壇前面時

論壇 2026-09-05 開了全站 Managed Challenge：每個路徑（連靜態圖片）都回
403 `cf-mitigated: challenge`，換 UA 沒用。

**試過但不夠的作法**：把 WebView 解出來的 `cf_clearance` 撈回 Dart 的
cookie jar（`WebViewCookieManager.getCookies` 兩個平台都讀得到 HttpOnly，
UA 也對齊了）。實測**還是 403**——票是真的，但 Cloudflare 也看 TLS 指紋，
拿票的必須真的是瀏覽器。症狀是驗證頁一直重複彈出。

**現在的作法**：連請求本身都交給 WebView。`lib/services/browser_fetch.dart`
維持一個常駐的 1×1 隱形 WebView，停在論壇頁面上，用 `fetch()` 發同源請求，
結果經 JavaScript channel 回 Dart，再餵給原本的解析器。

幾個必要條件：
- WebView **必須真的在 widget 樹裡**。iOS 的 WKWebView 不在畫面上時
  JavaScript 會被節流甚至完全不跑。掛在 `MaterialApp.builder` 的 Stack 裡，
  1×1、`IgnorePointer`。做 0×0 有些版本根本不初始化。
- 注入的 `window.__gmFetch` **每次呼叫前都要重新注入**：頁面一導覽 JS 環境
  就沒了，而挑戰頁本身就會導覽。
- 走 WebView 時**拿不到狀態碼與標頭**（`fetch()` 只回文字），所以「這是不是
  挑戰頁」只能比對內文特徵，見 `BrowserFetch.looksLikeChallenge`。
- **不能拿 `challenge-platform` 當攔截頁的依據。** Cloudflare 開啟 JS Detections
  之後會把 `/cdn-cgi/challenge-platform/scripts/jsd/main.js` 注入到**每一個
  正常頁面**。拿它判斷的話，每一頁論壇內容都會被當成攔截頁——症狀是驗證頁
  不斷跳出、使用者解了也沒用。攔截頁專屬的標記是 `_cf_chl_opt`。
- **不能用 `#hd`／`#nv`／`.bm`／`#ft` 認論壇頁面。** 那些是**桌面版** Discuz 的
  結構，手機模板一個都沒有（實測樣本裡全是 0），所以那支探測永遠判不出
  `forum`。手機版頁面裡一定有大量指向 `forum.php`／`home.php` 的連結，用那個。
- **判斷「挑戰解開了沒」不能看 `cf_clearance` 在不在**。上一次解出來的票會
  留在 cookie store 裡，於是驗證頁一打開就以為成功、立刻自己關掉——使用者
  看到的是驗證頁一閃而過。要探測**畫面上真的是論壇了**。
- **不能在第一個 `onPageFinished` 就當作就緒**：挑戰頁自己也會觸發那個事件。
- **全 App 只能有一顆 WebView**。發請求的和給使用者解驗證的必須是同一個——
  開兩顆的話，使用者在看得見的那顆解完，背後那顆還停在挑戰頁上，而它是透明的
  （連「我是人類」都點不到），於是永遠解不開。症狀是按了「我已完成」卻跳出
  「需要先通過論壇的安全驗證」。一個 controller 同時只能掛在一個
  `WebViewWidget` 上，所以驗證頁顯示時常駐的宿主要讓位（`presenting`）。
- **不要為了等挑戰解開而長時間阻塞**。驗證頁顯示的就是那同一顆 WebView，
  所以提早叫出來是零成本的：如果其實只是還在載入，載完的瞬間它會偵測到論壇
  並自己關閉。等十幾秒只會讓使用者對著空白轉圈圈。
- 宿主用 `Opacity(0)` 的正常尺寸，不要 1×1。Cloudflare 會量視窗尺寸當指紋，
  1×1 很可疑，真要點「我是人類」時也沒地方可點。
- **上次被擋著就在 App 啟動時預熱 WebView**（存在 SharedPreferences）。少了
  這步，第一個請求要先吃 403、再從零載入論壇頁、再等挑戰解掉，使用者對著
  轉圈圈等十幾秒。
- 撞過一次挑戰就固定走瀏覽器（`_preferBrowser`），不必每個請求都先吃一個
  403。但**每 10 分鐘會回頭探一次直連**，論壇關掉驗證就自己切回來——
  直連快得多，不該讓使用者一直付繞 WebView 的代價。探測成本只是偶爾多
  一個 403。（`Api.resetTransport()` 是手動切回，測試用。）

**網頁版救不了**：它的請求是從伺服器發出的，而 `cf_clearance` 綁的是解題
那台機器的 IP。使用者在自己瀏覽器上解的，拿到伺服器上不算數。網頁版因此
顯示不同的訊息，老實說「暫時無法連線」，不叫使用者去白忙。

## fetchBadges 失敗不能回 0

紅點只讀頁首（`fetchBadges`），它原本把 `DiscuzException` 吞掉並回 0。
呼叫端因此分不出「真的沒有未讀」和「這次沒抓到」，一次失敗就把已經顯示的
紅點蓋掉——症狀是**通知亮起來又瞬間消失**。網路穩的時候看不出來，換成繞
WebView 的傳輸之後就浮現了。現在讓它丟例外，三個呼叫處本來就都接住並保留
原本的數字。

## 走 WebView 傳輸時，圖片也要一起走

圖片本來是 Flutter 自己的 HTTP 堆疊在抓（`Image.network` /
`CachedNetworkImage`），**完全繞過傳輸層**。所以只把 `get`／`post` 導到
WebView 的話，症狀是「文字讀得到、圖片整片載入失敗」——子版塊圖示、頭像、
帖子裡的圖全都不見。

`BrowserFetch.fetchBytes` 在頁面裡把 blob 轉成 data URL 再經 JS 通道帶回來
（通道只能傳字串），Dart 端解 base64。會膨脹三分之一，所以 `NetImage` 自己
記一份小的記憶體快取——同一張頭像在列表裡會出現很多次。

## 發請求前要確定頁面停在論壇上

`_ensureOnForum`。少了它有兩種症狀：停在挑戰頁時 fetch 拿回的是挑戰 HTML；
而挑戰頁解題過程中會自己重新導向，把進行中的 fetch 一起取消——Safari 回報
「TypeError: Load failed」，看起來像網路斷了，其實只是在錯的時機發了請求。
那個錯誤不是 `CloudflareException`，所以也不會觸發自動重試，使用者得手動按。

