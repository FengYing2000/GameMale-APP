<div align="center">

<img src="assets/icon.png" width="112" alt="GameMale" />

# GameMale

**[GameMale 論壇](https://www.gamemale.com/) 的手機 App**

在手機上好好逛論壇 —— 深色模式、簽到、私訊、樓中樓，一個都不少

[![網頁版](https://img.shields.io/badge/網頁版-立即開啟-70A128?style=for-the-badge)](https://852111.xyz)
[![Android](https://img.shields.io/badge/Android-下載_APK-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-android-手機)
[![iPhone](https://img.shields.io/badge/iPhone-安裝說明-000000?style=for-the-badge&logo=apple&logoColor=white)](#-iphone)

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![iOS](https://img.shields.io/badge/iOS-15.0%2B-lightgrey?logo=apple&logoColor=white)](#-iphone)
[![Android](https://img.shields.io/badge/Android-6.0%2B-lightgrey?logo=android&logoColor=white)](#-android-手機)
[![測試](https://img.shields.io/badge/自動測試-356_項-4CAF50)](docs/DEVELOPING.md)

**繁體中文** · [简体中文](README.zh-CN.md)

</div>

---

## 這是什麼

GameMale 論壇沒有官方 App。用手機瀏覽器逛，字小、圖片吃流量、切換版塊要一直等整頁重載。

這個 App 把論壇的內容抓下來，**用手機介面重新畫一次**。它不是把網頁塞進 App 圖示裡的殼——
所以才做得到深色模式下文字真的看得清楚、圖片可以按流量決定要不要載、繁簡體隨時切換。

論壇上你會做的事，這裡幾乎都能做：看帖、回覆、發文、簽到、私訊、評分、投票、淘帖、群組。

---

## 開始使用

三種方式，**選一種就好**。不確定的話用網頁版，最省事。

| | 適合誰 | 要注意 |
|---|---|---|
| 🌐 **網頁版** | 所有人，尤其 iPhone | 不用安裝、不會過期、隨時是最新版 |
| 🤖 **Android** | Android 手機 | 下載一個檔案直接裝，不會過期 |
| 🍎 **iPhone 原生版** | 想要完全原生的體驗 | 需要電腦操作，**每 7 天要重裝一次** |

### 🌐 網頁版（最推薦）

用 **Safari** 開啟 **[852111.xyz](https://852111.xyz)**，然後加到主畫面：

1. 點瀏覽器右下角的 **「⋯」**
2. 選最上面的 **「分享」**
3. 往下捲，選 **「加入主畫面」**
4. 回到主畫面，從 GameMale 圖示打開

加完之後開起來沒有網址列、全螢幕、有自己的圖示，用起來就跟一般 App 一樣。
第一次開啟會多花幾秒下載中文字體，之後就不用了。

> **iPhone 為什麼推薦這個？** 因為原生 App 用免費的開發者憑證簽章，Apple 只給 7 天，
> 到期就打不開、要重新安裝一次。網頁版沒有這個問題。

### 🤖 Android 手機

到 **[Releases](../../releases)** 下載 `GameMale.apk`，點開安裝即可。
系統會問要不要允許安裝來源，同意就好。**不會過期。**

### 🍎 iPhone

原生版需要用電腦側載，而且**每 7 天要重簽一次**（Apple 對免費憑證的限制，不是 App 的問題）。

1. 到 **[Releases](../../releases)** 下載 `GameMale.ipa`
2. 用 [Sideloadly](https://sideloadly.io/) 或 [AltStore](https://altstore.io/) 安裝
3. 到「設定 → 一般 → VPN 與裝置管理」信任你的開發者憑證

嫌麻煩的話，**用上面的網頁版就好**，功能是一樣的。

---

## 功能

<table>
<tr>
<td width="150"><b>📖 瀏覽</b></td>
<td>版塊列表（可展開子版塊、點圖示看版主與版規）、主題列表可依<b>最新／熱門／精華</b>切換，也能只看投票或懸賞。帖子內頁支援分頁、附件、<b>樓中樓</b>，還能快速跳到指定樓層。</td>
</tr>
<tr>
<td><b>✍️ 發言</b></td>
<td>回覆、引用回覆、發表新主題、編輯自己的帖子。內建<b>表情選擇器</b>與 BBCode 快捷鍵，回帖有獎勵時會直接顯示橫幅。已經回過的主題會標「已回」。</td>
</tr>
<tr>
<td><b>⭐ 互動</b></td>
<td>評分、投票、頂／踩、收藏主題與版塊、使用道具（提升泵／亮色刷）、舉報。</td>
</tr>
<tr>
<td><b>📅 每日簽到</b></td>
<td>一鍵簽到，看得到<b>排行榜</b>與連續天數。有補簽卡可以補簽。也可以開「每天自動簽到」，每天第一次開 App 就幫你點好。</td>
</tr>
<tr>
<td><b>💬 私訊與提醒</b></td>
<td>私訊是<b>氣泡對話</b>介面，不是論壇那種列表。新訊息與新提醒會在底部顯示紅點。提醒可以直接回招呼或忽略。</td>
</tr>
<tr>
<td><b>👤 個人空間</b></td>
<td>個人資料（角色組、勳章、管理的版塊、加入的群組）、記錄廣場、日誌、相冊、好友。可以加好友、打招呼（14 種動作）。</td>
</tr>
<tr>
<td><b>📚 淘帖與群組</b></td>
<td>專輯的推薦／全部／我的，可訂閱、評分評論、向作者推薦主題、用標籤搜尋。自己建的專輯可以編輯、刪除、邀請維護。群組能加入／退出／收藏，看得到成員與積分排行。</td>
</tr>
<tr>
<td><b>🔍 搜尋</b></td>
<td>帖子、日誌、相冊、群組、淘帖、用戶都能搜，也能只搜本版。<b>單一個字也搜得到</b>。進階搜尋可指定作者、時間範圍與排序。</td>
</tr>
<tr>
<td><b>🎨 個人化</b></td>
<td>深色／淺色主題、<b>彩虹旗六色</b>強調色任選、繁簡體即時切換、圖片載入策略（一律載入／只在 Wi-Fi／手動）。長按圖片可以儲存、分享或複製連結。</td>
</tr>
</table>

### 不登入也能用

論壇本身允許訪客瀏覽，App 也一樣：**版塊、主題、帖子、記錄廣場、他人資料**不登入就看得到。

回覆、發文、評分、收藏、簽到、私訊這些要登入才能做——按鈕會直接隱藏，不會讓你填半天才說不行。

---

## 隱私

這是個人自用專案，不是官方 App，**與 GameMale 官方無關**。

- **不會保存你的密碼。** 登入後只留論壇給的 Cookie，跟你用瀏覽器登入是一樣的東西。
- **原生版直連論壇**，帳號密碼只送到 `www.gamemale.com`，不經過任何第三方。
- **網頁版經過一層轉發。** 瀏覽器有跨網域限制，不准網頁直接連論壇，所以請求會先經過
  `852111.xyz`（本專案自己架的）再送到論壇。**那台伺服器不保存任何帳號資料**——
  沒有資料庫、沒有你的 Cookie，登入狀態完全在你自己的瀏覽器裡。
- **沒有任何追蹤、廣告或數據收集。**

---

## 常見問題

<details>
<summary><b>網頁版和原生 App 有什麼差別？</b></summary>

功能完全一樣，同一份程式碼編出來的。差別只在：原生版直連論壇、可以離線快取圖片；
網頁版不用安裝、不會過期、永遠是最新版。iPhone 使用者建議直接用網頁版。
</details>

<details>
<summary><b>iPhone 版為什麼 7 天就打不開？</b></summary>

Apple 對免費開發者憑證的限制——用免費帳號簽的 App 只能跑 7 天。這不是 App 的問題，
所有側載的 App 都一樣。要免除這個限制得付 Apple 每年 99 美金的開發者帳號。
**用網頁版就沒有這個問題。**
</details>

<details>
<summary><b>會不會有推播通知？</b></summary>

沒有，而且是刻意拿掉的。原本做過兩套（原生背景檢查、網頁版的推播伺服器），
但 iOS 決定何時喚醒 App 的時機完全不可控，實際體驗是「該通知時不通知、半夜亂通知」，
而網頁版那套還得讓伺服器保存你的論壇 Cookie。權衡後整套移除了——
**這也是現在能說「伺服器不保存任何帳號資料」的原因。**
</details>

<details>
<summary><b>出現「論壇開啟了 Cloudflare 安全驗證」怎麼辦？</b></summary>

論壇有時會開啟 Cloudflare 的機器人防護，這時任何 App 都連不上，要用真的
瀏覽器通過一次驗證才行。

**原生版**會自動跳出一頁驗證，通過之後就恢復正常（通常等幾秒，有時要點
一下「我是人類」）。

**網頁版沒辦法自動處理。** 因為它的請求是從伺服器發出的，而 Cloudflare 發的
通行證綁定「解驗證那台機器的網路位址」——你在自己手機上通過的，伺服器那邊
不算數。這種時候只能改用 App 版，或等論壇關閉驗證。
</details>

<details>
<summary><b>圖片很吃流量怎麼辦？</b></summary>

設定 → 流量 → 帖子圖片載入，可以選「只在 Wi-Fi 載入」或「手動」。
選手動時圖片會先顯示佔位，點一下才載入。
</details>

<details>
<summary><b>介面可以變簡體嗎？</b></summary>

可以，設定裡切換，整個介面會立刻重繪。
但**帖子內容一律保留作者原本的用字**——轉換過的標題跟論壇上對不起來，找不到帖。
想看轉換後的內容，在帖子頁上按「翻譯」，那是逐篇的。
</details>

---

## 給開發者

架構、技術取捨、以及十幾輪實作累積的踩雷筆記在 **[docs/DEVELOPING.md](docs/DEVELOPING.md)**。
網頁版後端（論壇轉發、圖片代理、中文字體處理）在 **[pwa/README.md](pwa/README.md)**。

一句話版本：Flutter 寫的，論壇官方手機 API 已關閉，所以解析 `?mobile=2` 的手機版 HTML；
解析層抽成純 Dart 套件 `packages/gm_api`，原生版與網頁版後端共用同一份。

```bash
flutter test                                        # 293 項
cd packages/gm_api && dart test                     # 35 項
cd pwa/server && dart test                          # 28 項
```

---

## 授權

個人自用專案。簡繁對照資料衍生自 [OpenCC](https://github.com/BYVoid/OpenCC)（Apache-2.0），
用字判斷與台灣詞彙為本專案自訂。

App 圖示與論壇內容的版權屬於 GameMale 及各自的作者。
