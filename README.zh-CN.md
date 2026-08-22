<div align="center">

<img src="assets/icon.png" width="96" alt="GameMale" />

# GameMale for iOS

**[GameMale](https://www.gamemale.com/) 论坛的原生 iOS 客户端**

Flutter 打造 · 直连论坛 · 不经第三方服务器

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![iOS](https://img.shields.io/badge/iOS-15.0%2B-000000?logo=apple&logoColor=white)](#产出-ipa)
[![Tests](https://img.shields.io/badge/测试-165%20项-4CAF50)](#测试策略)
[![License](https://img.shields.io/badge/用途-个人自用-lightgrey)](#授权与隐私)

[繁體中文](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## 这是什么

GameMale 官方没有 App，App Store 上的「论坛助手」是通用型 Discuz 客户端，体验不佳。
这个项目把论坛做成一个真正好用的 iOS App：原生界面、深色模式、繁简切换、流量控制，
以及论坛本身的完整功能 —— 签到、评分、楼中楼、投票、私信、记录广场。

> **为什么不是套壳浏览器？**
> 那样只是把网页塞进 App 图标里。这个项目解析论坛数据后用原生组件重绘，
> 才能做到深色模式下文字可读、图片按流量策略加载、繁简即时切换这些网页版做不到的事。

---

## 技术取舍

### 为什么是解析 HTML，不是调 API

探测结果很明确 —— 该站的官方 Discuz 手机 API **已被关闭**：

```http
GET /api/mobile/index.php?version=4&module=forumindex
→ 200 OK，响应长度 0
```

PHP 确实执行了（会返回 `Set-Cookie`），但所有 JSON 模块都返回空字符串，
只有 `mynotelist` 漏出老旧的 WAP 模板。

所以走第二条路：带 `mobile=2` 取手机版模板（`xinrui_iuni_mobile/touch`），
再用 `package:html` 解析。手机版模板只有 **37 KB**（桌面版 187 KB），节点结构干净。

### 几个关键决定

| 决定 | 原因 |
|---|---|
| **登录状态只认登出链接** | 游客版底部导航也有 `mycenter=1` 的「我的」，拿它当证据会把游客判成已登录 |
| **判定游客要看到登录入口** | `inajax=1` 的浮层片段两种标记都没有，用「缺少登出链接」反推会害用户一点评分就被登出 |
| **需要登录要看 `#loginform`** | 游客浏览公开版块时页脚一样有登录链接，用它会把每个版块都拦掉 |
| **验证码走 `getBytes` + `Image.memory`** | `Image.network` 不会带 session cookie，拿到的验证码跟服务器记的对不上 |
| **发帖走桌面端点** | 论坛处理逻辑相同，但插件（勋章积分）挂在桌面流程上 |
| **繁简转换自定规则** | OpenCC 的第一候选常常不合语境（`签到`→`籤到`、`295 里`→`295 裡`） |

---

## 功能

<table>
<tr><td width="90"><b>浏览</b></td><td>版块列表 · 主题列表（全部／最新／热门／精华）· 主题分类 · 子版块 · 帖子内页 · 分页</td></tr>
<tr><td><b>互动</b></td><td>回复 · 引用回复 · 发表主题 · 编辑自己的帖子 · 收藏 · 评分（快速评分／自动跳过缺项）· 投票</td></tr>
<tr><td><b>社区</b></td><td>私信（气泡对话）· 通知（两层分类）· 个人资料 · 加好友 · 打招呼 · 记录广场</td></tr>
<tr><td><b>账号</b></td><td>账密登录（图形验证码／安全提问）· 登出 · 每日签到 · 我的收藏／主题／回复</td></tr>
<tr><td><b>体验</b></td><td>深／浅色 · 繁简切换 · 流量控制 · 图片长按菜单 · 楼中楼 · 固定分页栏 · 下拉刷新</td></tr>
</table>

### 游客与会员

论坛本身允许游客浏览，App 忠实反映这一点：

- **游客可看**：版块、主题、帖子、记录广场（随便看看）、他人资料
- **需要登录**：回复、发帖、编辑、评分、收藏、签到、私信、发布记录、通知

写入动作有三道防线：提交结果会识别登录墙、动手前先确认、UI 直接隐藏按钮。

---

## 架构

```
lib/
├── api/
│   ├── models.dart      所有数据类型（空安全，UI 拿不到 dynamic）
│   ├── http.dart        dio + PersistCookieJar，cookie 落地免重登
│   ├── parse.dart       DOM 工具、内容净化、登录状态判定
│   └── discuz.dart      所有端点；纯解析函数独立导出方便测试
├── i18n/
│   ├── s2t.dart         简→繁（台湾用语）
│   └── ui.dart          界面繁→简
├── store/               session（登录状态）· settings（语言／主题／流量）
└── ui/
    ├── widgets/         PostBody · ThreadTile · Avatar · StateBox · StickyPager …
    └── pages/           18 个页面

tool/
├── zh_rules.py          繁简转换的人工规则 ← 要调整用字改这里
├── build_zh_table.py    生成 assets/s2t.json
├── fetch_fixtures.dart  重抓测试样本
├── make-icon.mjs        生成 App 图标（纯 Node）
└── build-ipa.sh         在任一台 Mac 上产 IPA
```

---

## 测试策略

论坛随时可能改版，选择器一坏画面就空白。所以测试不是形式，而是**用真实页面验证解析器**。

| 文件 | 内容 | 数量 |
|---|---|---|
| `parse_test.dart` | 用真实抓下来的页面验证每个选择器 | 约 110 |
| `render_test.dart` | 真实帖子 HTML 丢进 PostBody 确认画得出来 | 12 |
| `pages_test.dart` | 每页 pump 起来 + 离线行为 | 20 |
| `s2t_test.dart` | 繁简转换的每一类判断 | 18 |
| `live_test.dart` | 对真实论坛的端到端（需 cookie，CI 自动跳过） | 14 |

```bash
flutter test                        # 165 项离线测试
flutter analyze                     # 零问题
```

**论坛改版时：**

```powershell
$env:GM_COOKIE = "TVj0_2132_auth=...; TVj0_2132_saltkey=..."
$env:GM_UID = "677863"
dart run tool/fetch_fixtures.dart   # 重抓样本
flutter test                        # 坏掉的选择器会直接指名
```

---

## 开发

需要 Flutter SDK 3.47 以上。

```bash
flutter pub get
flutter analyze
flutter test
```

> [!IMPORTANT]
> **Windows 上必须把项目放在纯 ASCII 路径**（例如 `C:\src\gamemale`）。
> 路径含中文时 Dart 分析服务器会崩溃 —— LSP 消息长度按字符数算、实际传输按字节数，
> 中文百分号编码后对不上。这是工具链限制，不是配置问题。

### 调整繁简用字

不需要动代码，改 [`tool/zh_rules.py`](tool/zh_rules.py) 即可：

```python
EXCLUDE       # 完全不转的字：里 台 范 谷 尸 姜 …
CHAR          # 一对多时选哪个：签→簽（不是籤）
DISAMBIGUATE  # 逐字会错的词：这里→這裡、头发→頭髮
TAIWAN        # 台湾用语：软件→軟體、鼠标→滑鼠、链接→連結
```

```bash
python tool/build_zh_table.py       # 重新生成 assets/s2t.json
flutter test test/s2t_test.dart     # 验证
```

> 4012 个简体字里 3736 个是一对一（`国→國`），没有判断空间；
> 只有 276 个一对多的会转错，规则文件只管这些。

---

## 产出 IPA

编译 iOS 一定要 macOS —— 换框架、装插件都绕不过去，因为最后一步要链接 iOS SDK、
跑 `actool` 编素材，那些二进制文件只在 macOS 上发行。

但**不一定要用 GitHub**。

### 方式一：任一台 Mac

```bash
chmod +x tool/build-ipa.sh
./tool/build-ipa.sh
```

脚本会检查 Xcode、必要时自动装 Flutter、跑分析与测试、产出 `GameMale.ipa`。

### 方式二：GitHub Actions

推上 `main` 自动构建，或在 Actions 页手动触发，完成后从 Artifacts 下载。

```bash
gh run download <run-id> -n GameMale-unsigned-ipa -D ./out
```

> [!NOTE]
> 私有 repo 的 macOS runner 用量按 **10 倍**计。免费额度 2000 分钟 ≈ 200 分钟 macOS，
> 一次构建约 5 分钟，大约每月 40 次。公开 repo 免费不限量。

### 侧载

产出的是**未签名 IPA**，三种方式择一：

| 工具 | 适用 | 特点 |
|---|---|---|
| **Sideloadly** | Windows | 接手机、拖入 IPA、填 Apple ID |
| **AltStore / SideStore** | 跨平台 | 可自动续签，免费账号到期前自动重签 |
| **ESign / TrollStore** | 手机端 | 不用电脑 |

免费 Apple ID 证书 7 天到期，**重签用同一个 IPA 即可，不必重编**。

---

## 目前没做的部分

- **发帖上传图片／附件** — Discuz 的 `swfupload` 是 multipart 端点，没有真机无法验证
- **搜索的日志／相册／群组／用户分类** — 目前只有帖子搜索
- **个人空间子页**（动态／日志／相册／留言板）与完整个人资料字段
- **回帖奖励、外部链接跳转提示、表情选择器**
- **推送通知** — 需要自建推送服务器与 APNs 证书，自签 App 拿不到

---

## 授权与隐私

个人自用项目，非官方、与 GameMale 官方无关。

账号密码只会发送到 `www.gamemale.com`，cookie 存在 App 沙箱内，不连任何第三方服务。

`Info.plist` 开了 `NSAllowsArbitraryLoads` —— 帖子图片来自用户贴的任意外站网址，
无法列举白名单。这是侧载自用的 App，不上架，故如此取舍。

繁简对照数据衍生自 [OpenCC](https://github.com/BYVoid/OpenCC)（Apache-2.0）的字符对应表，
用字判断与台湾词汇为本项目自定。
