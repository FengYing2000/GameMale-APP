<div align="center">

<img src="assets/icon.png" width="96" alt="GameMale" />

# GameMale for iOS

**[GameMale](https://www.gamemale.com/) 論壇的原生 iOS 客戶端**

以 Flutter 打造 · 直連論壇 · 不經第三方伺服器

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![iOS](https://img.shields.io/badge/iOS-15.0%2B-000000?logo=apple&logoColor=white)](#產出-ipa)
[![Tests](https://img.shields.io/badge/測試-242%20項-4CAF50)](#測試策略)
[![License](https://img.shields.io/badge/用途-個人自用-lightgrey)](#授權與隱私)

[繁體中文](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## 這是什麼

GameMale 官方沒有 App，App Store 上的「论坛助手」是通用型 Discuz 客戶端，體驗不佳。
這個專案把論壇做成一個真正好用的 iOS App：原生介面、深色模式、繁簡切換、流量控制，
以及論壇本身的完整功能 —— 簽到、評分、樓中樓、投票、私訊、記錄廣場。

> **為什麼不是套殼瀏覽器？**
> 因為那樣就只是把網頁塞進 App 圖示裡。這個專案解析論壇資料後用原生元件重繪，
> 才能做到深色模式下文字可讀、圖片依流量策略載入、繁簡即時切換這些網頁版做不到的事。

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
| **深色底的灰字要明講顏色** | 回 `null` 等於不覆寫，元素上的 `color="#333"` 還是會生效 |
| **論壇頁面用內建瀏覽器** | 丟給系統瀏覽器那邊沒有登入狀態，所以把 App 的 cookie 灌進 WebView |
| **論壇內容一律保留原文** | 轉過的標題跟網頁版對不起來，所以簡繁轉換改成帖子頁上逐篇按 |
| **取消收藏是兩步驟** | 先 GET 拿確認表單（formhash 跟頁面上的不同），再 POST `deletesubmit=true` 才真的刪 |
| **ajax 回應要抽訊息** | 整包只是一段 `<script>`，直接當文字會把 JavaScript 唸出來 |
| **圖片有三種來源** | 一般網址、`data:` 內嵌、jsdelivr 的 `.svg` emoji；後兩種要各自的解碼路徑，否則整片「載入失敗」 |
| **附件也有三種長相** | 帖尾的 `dl.tattl`、內文中間的 `span#attach_N`、「更多圖片」的 `dl.tattl.attm`（要排除） |
| **附件內容自己解碼** | 伺服器送 `octet-stream` 又不帶 charset，瀏覽器在繁中系統會猜成 Big5，UTF-8 檔就變亂碼 |
| **分頁要記住請求的頁數** | 有些列表只給「上一頁／下一頁」，照 DOM 算會永遠停在第 1 頁，還把下一頁的 `page=3` 當成總頁數 |
| **刪除都是兩步驟** | 先 GET 拿確認表單（formhash 跟頁面上的不同），再 POST 才真的刪；抽成 `confirmAndSubmit` 共用 |
| **群組是另一套頁面** | `group-<fid>-1.html` 只有桌面模板，用 `/f/<fid>` 進去會顯示「沒有主題」 |
| **簡繁轉換自訂規則** | OpenCC 的第一候選常常不合語境（`签到`→`籤到`、`295 里`→`295 裡`） |

---

## 功能

<table>
<tr><td width="90"><b>瀏覽</b></td><td>板塊列表（收藏的版塊／子版塊展開）· 主題列表（全部／最新／熱門／熱帖／精華）· 投票與懸賞篩選 · 排序與時間範圍 · 主題分類 · 帖子內頁 · 附件 · 分頁</td></tr>
<tr><td><b>互動</b></td><td>回覆 · 引用回覆 · 發表主題 · 編輯自己的帖子 · 收藏 · 評分（快速評分／自動跳過缺項）· 投票</td></tr>
<tr><td><b>社群</b></td><td>私訊（氣泡對話）· 通知（兩層分類）· 個人資料（角色組／勳章／管理版塊／已加入群組）· 個人空間七個子頁 · 加好友 · 打招呼 · 記錄廣場</td></tr>
<tr><td><b>搜尋</b></td><td>帖子 · 日誌 · 相冊 · 群組 · 用戶 · 本版搜尋 · 高級搜索（全文／作者／主題範圍／特殊主題／時間／排序）</td></tr>
<tr><td><b>帳號</b></td><td>帳密登入（圖形驗證碼／安全提問）· 註冊問答 · 登出 · 每日簽到 · 我的收藏／主題／回覆 · 回帖紀錄</td></tr>
<tr><td><b>體驗</b></td><td>深／淺色 · 六色強調色 · RPG 風格提示氣泡 · 繁簡切換 · 流量控制 · 表情選擇器 · 外部連結跳轉提示 · 回帖獎勵橫幅 · 已回帖標記 · Lucide 圖示 · 內建瀏覽器（帶登入狀態）· 圖片長按選單 · 樓中樓 · 固定分頁列 · 下拉重新整理</td></tr>
</table>

### 訪客與會員

論壇本身允許訪客瀏覽，App 忠實反映這一點：

- **訪客可看**：板塊、主題、帖子、記錄廣場（隨便看看）、他人資料
- **需要登入**：回覆、發文、編輯、評分、收藏、簽到、私訊、發布記錄、通知

寫入動作有三道防線：送出結果會辨識登入牆、動手前先問一次、UI 直接藏掉按鈕。

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
    └── pages/           21 個頁面

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
| `parse_test.dart` | 用真實抓下來的頁面驗證每個選擇器 | 181 |
| `pages_test.dart` | 每頁 pump 起來 + 離線行為 | 30 |
| `s2t_test.dart` | 簡繁轉換的每一類判斷 | 18 |
| `render_test.dart` | 真實帖子 HTML 丟進 PostBody 確認畫得出來 | 12 |
| `live_test.dart` | 對真實論壇的端對端（需 cookie，CI 自動略過） | 43 |

```bash
flutter test                        # 242 項離線測試
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

## 目前沒做的部分

- **發文上傳圖片／附件** — Discuz 的 `swfupload` 是 multipart 端點，沒有實機無法驗證
- **下載附件** — 點了交給瀏覽器；App 沙箱存不了任意檔案，付費附件也要在論壇頁面上完成交易
- **註冊最後一步** — 答題通過後的帳號／信箱／驗證碼表單交給瀏覽器。論壇目前關閉註冊，這條路徑無法驗證，寧可不寫沒把握的程式碼
- **推播通知** — 需要自架推播伺服器與 APNs 憑證，自簽 App 拿不到

---

## 授權與隱私

個人自用專案，非官方、與 GameMale 官方無關。

帳號密碼只會送到 `www.gamemale.com`，cookie 存在 App 沙箱內，不連任何第三方服務。

`Info.plist` 開了 `NSAllowsArbitraryLoads` —— 帖子圖片來自使用者貼的任意外站網址，
無法列舉白名單。這是側載自用的 App，不上架，故如此取捨。

簡繁對照資料衍生自 [OpenCC](https://github.com/BYVoid/OpenCC)（Apache-2.0）的字元對應表，
用字判斷與台灣詞彙為本專案自訂。
