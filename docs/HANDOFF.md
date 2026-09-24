# GameMale 客戶端 — 交接文件

> 給接手的新對話快速上手用。最後更新：2026-09-22，版本 **1.29.0+78**。
> 這份是「整體狀態 + 怎麼繼續」；技術踩坑細節在 [DEVELOPING.md](DEVELOPING.md)，
> 使用者面向說明在 [../README.md](../README.md)，長期記憶在 `~/.claude/.../memory/`
> 的 `project_gamemale_ios` / `project_gamemale_pwa` / `reference_gamemale_cf_gate`。

---

## 這是什麼

GameMale 論壇（`https://www.gamemale.com/`，Discuz! X，簡體站）的非官方手機客戶端。
論壇官方 mobile API 已關閉，所以**解析 `?mobile=2` 的手機版 HTML**。三種形態、同一份 code：

| 形態 | 說明 |
|---|---|
| **原生版** | Flutter iOS(IPA)/Android(APK)，**直連論壇** |
| **網頁版** | `flutter build web --wasm` 掛在 `https://852111.xyz`，經 VPS 轉發（瀏覽器不能跨網域打論壇）|
| — | 解析層抽成純 Dart 套件 `packages/gm_api`，三邊共用 |

**專案位置**：`C:\src\gamemale`（**路徑必須純 ASCII**，否則 Dart 分析伺服器崩潰）。
Flutter SDK 在 `C:\src\flutter`（bash PATH 沒有，用 `C:/src/flutter/bin/dart.bat` / `flutter.bat`）。
**Repo**：`FengYing2000/GameMale-APP`（公開）。使用者 GitHub 主帳號是 `LaiYueJi`，但 repo owner／
所有 commit 作者都是 `FengYing2000`（兩個不同帳號）。

---

## 架構

```
packages/gm_api/          純 Dart，不依賴 Flutter（PWA 後端也要用）
  lib/http.dart           連線層 Api（dio）、UA、CF 偵測 isChallengeHtml、cookie
  lib/discuz.dart         6000+ 行解析（parseThread/parseIndex/...），選擇器知識都在這
  lib/models.dart         資料模型
  lib/s2t.dart            簡→繁轉換（S2T）
lib/                      Flutter App
  store/session.dart      登入狀態
  store/accounts.dart     多帳號（切換/新增/登出重登/排序）
  services/browser_fetch.dart  被 CF 擋時用 WebView 當傳輸（原生版）
  ui/pages/               各頁面
  i18n/ui.dart            tr()＝繁→使用者語言；sys()＝論壇內容→使用者語言
pwa/server/               網頁版後端（shelf）：/gm 轉發、/gmimg 圖片代理、限流
  bin/server.dart, lib/forum_proxy.dart, lib/rate_limit.dart, lib/asset_guard.dart
```

---

## 操作手冊

### 驗證（每次改完必跑）
```bash
"C:/src/flutter/bin/flutter.bat" analyze lib/
"C:/src/flutter/bin/flutter.bat" test                      # App，~305 項
cd packages/gm_api && "C:/src/flutter/bin/dart.bat" test   # ~59 項
cd pwa/server    && "C:/src/flutter/bin/dart.bat" test     # ~38 項
```
※ auto mode 有時會擋 dart/flutter 執行，多試一次或換 PowerShell；擋 git commit 同理。

### 出原生版（commit + push 觸發 CI）
- CI 只有 `.github/workflows/{android,ios}.yml`；**`paths-ignore: pwa/**、**.md`**，所以純 server／文件改動不觸發 App build。
- iOS runner 必須 `macos-26`（有些套件用 iOS 26 SDK）。
- 每輪 **bump `pubspec.yaml` version**，**commit 訊息不加任何 AI 署名**（使用者為此重寫過 84 個 commit，很認真）。
- 監看：`gh run watch <id> --exit-status`。下載：
  `gh run download <id> -n GameMale-unsigned-ipa` / `-n GameMale-apk`。

### 部署網頁版（VPS，手動，**沒有 CI**）
VPS：`160.236.111.8`（root 密碼登入，密碼走 `VPS_PASS` 環境變數，**絕不寫進檔案**）。
站點在 `/opt/stacks/gamemale-pwa`（**不是 git repo**，SFTP 上傳），Dockge + Caddy + docker compose。
scratchpad 有 `vps.py`（SSH exec，stdin 餵命令）、`sftp_sync.py`（同步 gm_api/lib + pwa/server + bin）。
```bash
export VPS_PASS='...' PYTHONIOENCODING=utf-8
python .../sftp_sync.py                      # 同步檔案
echo 'cd /opt/stacks/gamemale-pwa && docker compose build && docker compose up -d' | python .../vps.py
```
- **VPS 沒有 flutter/dart**；前端沒改就不用重傳 `build/web`。
- VPS 用 `dart:stable`（比本機新），const 求值更嚴——本機能編不代表 VPS 能編，以 `docker compose build`（內含 `dart analyze && dart test`）為準。
- Git Bash 對 `/opt/...` 會做路徑改寫；SFTP 路徑寫死在 py 裡、命令走 stdin 避開。
- `852111.xyz` 直連 Caddy、**沒有 Cloudflare**（真實 IP 在 `X-Forwarded-For`）。

---

## 目前功能狀態（都已上線驗證）

瀏覽／回覆／發文／編輯／評分／投票／收藏／簽到（排行榜＋補簽卡＋每天自動簽到）／
私訊／通知（紅點）／記錄廣場／日誌／相冊／搜尋／個人空間／道具買賣／淘帖／群組／
首頁在線會員卡。**通知系統 2026-09-04 整套移除**，是純瀏覽 App。

近期加的：
- **多帳號**：切換／新增／登出後用記住密碼重登／拖動排序（見下節）。
- **記住密碼**（可選）：`flutter_secure_storage` 存 iOS Keychain / Android Keystore，**皆存本機、不上 VPS**、網頁版停用。
- **UI 繁簡**：`sys()` 把論壇系統文字（版塊名、專輯統計）轉成使用者語言；帖子標題/內文/專輯名保留原文。
- **帖子懸賞**（悬赏提问）：`.rewardTit` → 金額＋未解決/已解決橫幅。
- **網頁版限流**：`/gm` 每 IP 120/分鐘，防被當免驗證跳板。
- **回帖成敗判定重寫**（1.28.0）：桌面版提示頁開頭永遠有隱藏的 `#main_succeed`（空 `.alert_right`＋「如果您的浏览器没有自动跳转」），
  舊的 `noticeMessage` 照文件順序抓到它、`_submitResult` 又拿整頁比對 `succeed` → **論壇擋下的回帖全被報成成功**。
  現在 `noticeOf()` 先看 `#messagetext`；回帖／發帖用 `expectThread`，看不懂的提示＝失敗；回帖再看不出成敗就去
  `goto=lastpost` 找自己的 uid＋內文片段確認（2026-06-11 起論壇有每日回帖上限，擋下的原句沒抓到過，所以不靠關鍵字）。
- **回覆頁先問 `replyGate`**：要一次桌面版回覆表單 → 不能回就是論壇的提示（主題關閉等）；能回就讀 `postminchars`／`postmaxchars`
  （GameMale 是 25／50000 **位元組**，中文一字 3）顯示字數、送出前先擋。
- **閱讀權限不足的帖子**：論壇回提示頁、沒有樓層，`ThreadData.message` 帶出原話（以前是一片空白）。
  **關閉的主題**：桌面版回帖框換成「您现在无权发帖」→ `replyBlocked`，回覆鈕變鎖頭、點了顯示原因。
  **手機版列表沒有**「[阅读权限 N]」與鎖頭，只有桌面版列表（淘專輯、群組、我的主題）標得出來；
  手機版列表的閱讀權限靠「已回」查詢（`authorid=自己`）撞到權限提示頁時順便得知（`parseAuthorView`）。
- **「已回」只認看得到樓層**（1.28.1）：以前是「沒有未定义操作就算回過」，權限不足／被刪的提示頁全被標成已回。
- **網頁版量高度的補救以前從沒生效**（1.28.1）：Flutter 網頁引擎**只聽 `visualViewport` 的 resize**
  （iOS 上量 `documentElement.clientHeight`），`index.html` 卻對 `window` 發 resize。改對 visualViewport 發，
  並每秒比對 clientWidth/Height、變了就重量。症狀是主畫面 App 偶爾畫面比螢幕高、底部頁碼列與按鈕被切掉。
- **網頁版不能把轉發網址（`852111.xyz/gm/...`）整頁交給瀏覽器開**（1.28.2）：論壇每頁帶
  `<base href="https://www.gamemale.com/">`，頁內連結全直連本站（瀏覽器沒登入 → 換頁變訪客、跳 CF），
  圖片來源是 852111.xyz 又被論壇**防盜連擋成 403**（實測：Referer 852111.xyz→403、本站或無→200）。
  一律用 `forumUrl()` 換回本站；代價是瀏覽器要另外登入論壇一次（使用者選的做法，沒走整站轉發）。

---

## App 控制台：測試碼／維護／更新（1.29.0 起）

後端在網頁版那台（`pwa/server/lib/control/`），**後台網址 `https://852111.xyz/admin`**。
- 資料：VPS 的 `/opt/stacks/gamemale-pwa/data/control.json`（＋`secret.key` 簽 token 用）。
  密碼與部署金鑰在同目錄 `.env`（`GM_ADMIN_PASSWORD`／`GM_DEPLOY_TOKEN`），**都不進版控**。
- 存的是測試碼與 App 自己產生的隨機裝置 ID，**不是論壇帳號**。
- **需要測試碼**開關：原生版只能在啟動時擋（`lib/store/gate.dart`，快取＋7 天離線寬限）；
  網頁版在伺服器端擋 `/gm`、`/gmimg`（403 beta／503 maintenance），`Api.onGate` 讓 App 立即蓋上畫面。
- 自己的 cookie 一律 `gmx_` 開頭，`ForumProxy` 轉發時濾掉。後台 cookie Path=/api/admin、SameSite=Strict，
  改資料要帶 `X-GM-Admin: 1`（防跨站偽造）。
- 「維護時可用」的碼（bypass）維護期間照樣能用，給自己測試。

### 發版流程
1. `pubspec.yaml` 改版本、`CHANGELOG.md` 寫這版內容（給使用者看；App 內更新日誌、下載頁、SideStore 都讀它）→ commit → push
2. `git tag vX.Y.Z && git push origin vX.Y.Z` → iOS（**只在標籤／手動觸發時建**，repo 私有後 macOS 算 10 倍）＋Android 建置
3. `python tool/publish_release.py` → 等建置 → 安裝檔上傳到**公開、只放安裝檔**的 `FengYing2000/GameMale-Releases` →
   登記到控制台（部署金鑰在 `tool/.deploy_token`，gitignore）
- SideStore 來源：`https://852111.xyz/api/app/source.json`（從控制台登記的版本動態產生）。
- 臨時要一份 IPA 給自己：`gh workflow run ios.yml`。

## CF 驗證的完整演進 ⚠️（最容易踩雷，務必讀）

論壇裝了 Discuz 外掛 `dev8133_cloudflare`，**伺服器端**（不是 CF 邊緣）擋 Turnstile，回 200。

1. 一度靠補固定 cookie `TVj0_2132_cloudflare_check=1` 繞過 → **2026-09-09 管理員改機制後失效**。
2. 現行規則＝**只放行「真正已登入的 session」**（有 `auth` cookie）＋**UserAgent 白名單**。
3. **App 的 UA 尾巴帶 `GameMaleApp/1.0`**（`gm_api` 的 `_ua`），管理員已把 `GameMaleApp` 加白名單 → 訪客請求也放行。
   - **原生版**：dio 直接用 `_ua`；被擋時走 WebView，三個 WebViewController 也 `setUserAgent(Api.userAgent)`。
   - **網頁版**：`ForumProxy` **會覆蓋**送往論壇的 UA 成 `Api.userAgent`（原本照抄瀏覽器 Safari UA 會被擋——踩過）。
4. **`isChallengeHtml` 只看結構、不憑內容關鍵字**：攔截頁 `<title>` 是「请稍候」、頁面只有幾 KB。
   CODE. 板塊有討論 CF 的技術帖，正常頁內容就帶 `dev8133_cloudflare`/`turnstile`/`请稍候`，舊的寬鬆比對把整頁誤判成挑戰（de0bd7c 修）。
5. 安全：UA 藏不住（抓包就有），開源邊際風險有限；真正風險是 `852111.xyz/gm` 這個公開轉發被當跳板 → 已加限流。

---

## 多帳號系統（`store/accounts.dart`）

- 每帳號在**本機**存 `{uid, name, avatar, username, cookies(快照), remember}`（SharedPreferences）；密碼另存安全區。**網頁版整個停用**（`kIsWeb` 早退）。
- **切換 = 換 cookie**：`switchTo` 把目標帳號 cookie 灌進 Dart jar **和 WebView**（`BrowserFetch.setCookies`），再 `checkSession` 驗證；失效回 `SwitchResult.needLogin`，UI 帶去 `/login?relogin=<uid>` 帳密自動填、一鍵重登。
- **cookie 快照必須撈 WebView 的 auth**：被 CF 擋時登入是在 WebView 完成的，`auth` 只在 WebView cookie store，`allCookies()`（Dart jar）讀不到。`_currentCookieHeader` 合併 Dart jar ∪ `BrowserFetch.exportCookies()`（WebView 優先）。少了這步，切換後變訪客、跳驗證。
- **新增帳號先 `beginAdd()`**（清成訪客）才登得了另一個帳號；不清的話 `checkSession` 看到舊 session、隨便輸入都「成功」、也不出驗證碼。
- **已登入時 `/login` 會被 router 重導回首頁**，所以新增／重登要帶 `?add=1`／`?relogin=` 讓 redirect 放行。
- 升級無痛：`syncFromSession` 把現有登入收為第一個帳號，並以「當前實際登入的帳號」為 current（不會亂切第一個）。

---

## 繁簡三分（使用者的原則，別搞錯）

- `tr('繁體字串')`：**App 自己的 UI 文案**（一律繁體寫，簡體模式即時轉）。
- `sys('論壇內容')`：論壇的**系統性**文字（版塊名、專輯統計標籤）→ 轉成使用者選的語言。
- **原文保留**：帖子標題、內文、專輯名、使用者發的內容 → **不轉**（轉了跟論壇對不起來、找不到帖）。

---

## 待辦 / 未決

- **自動更新 / 檢測更新 / 區分 release·beta·dev 線路**（使用者要求，**尚未做**）：
  iOS 側載無法 App 內自動安裝（只能檢測版本＋給下載連結，用側載工具重簽）；Android 可 App 內下載 APK ＋ intent 安裝。
  需要先建發布機制（目前 repo **沒有 Releases**，只有 Actions artifact）。這是接手後最可能的下一個大任務。
- **待使用者實測回報**：CODE. 板塊（de0bd7c 修完）、登出後切回帳號、拖動排序、懸賞顯示。
- 貢獻者 `LaiYueJi` 曾殘留在 GitHub 網頁快取（git 歷史已 100% 乾淨），已用重命名分支觸發重建。
- 從沒真的執行過：附件購買 submit、道具買/用 submit（會花真金幣）。

---

## 慣例與雷區速查

- **commit 不加 AI 署名**；每輪 **bump version**；commit 訊息用繁體、多行走 `git commit -F 檔案`。
- UI 繁體台灣用字，論壇內容用 `sys()`/原文（見上）。
- README 繁（`README.md`）＋簡（`README.zh-CN.md`）兩份。
- Android：`INTERNET` 權限要自己寫進 manifest；`flutter_secure_storage` v11 要 `compileSdk 37 + minSdk 24`（AGP 9.1.0 支援）。
- **`flutter build` 會編所有平台的 plugin dart**（連 iOS/Android build 都會編 windows plugin）——別用 `dependency_overrides` 壓 win32，會連 iOS 一起編爆。
- 更多踩坑：[DEVELOPING.md](DEVELOPING.md) 與 memory 條目。
