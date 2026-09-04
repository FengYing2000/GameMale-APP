<div align="center">

<img src="assets/icon.png" width="112" alt="GameMale" />

# GameMale

**[GameMale 论坛](https://www.gamemale.com/) 的手机 App**

在手机上好好逛论坛 —— 深色模式、签到、私信、楼中楼，一个都不少

[![网页版](https://img.shields.io/badge/网页版-立即打开-70A128?style=for-the-badge)](https://852111.xyz)
[![Android](https://img.shields.io/badge/Android-下载_APK-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#-android-手机)
[![iPhone](https://img.shields.io/badge/iPhone-安装说明-000000?style=for-the-badge&logo=apple&logoColor=white)](#-iphone)

[![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![iOS](https://img.shields.io/badge/iOS-15.0%2B-lightgrey?logo=apple&logoColor=white)](#-iphone)
[![Android](https://img.shields.io/badge/Android-6.0%2B-lightgrey?logo=android&logoColor=white)](#-android-手机)
[![测试](https://img.shields.io/badge/自动测试-349_项-4CAF50)](docs/DEVELOPING.md)

[繁體中文](README.md) · **简体中文**

</div>

---

## 这是什么

GameMale 论坛没有官方 App。用手机浏览器逛，字小、图片吃流量、切换版块要一直等整页重载。

这个 App 把论坛的内容抓下来，**用手机界面重新画一次**。它不是把网页塞进 App 图标里的壳——
所以才做得到深色模式下文字真的看得清楚、图片可以按流量决定要不要加载、繁简体随时切换。

论坛上你会做的事，这里几乎都能做：看帖、回复、发帖、签到、私信、评分、投票、淘帖、群组。

---

## 开始使用

三种方式，**选一种就好**。不确定的话用网页版，最省事。

| | 适合谁 | 要注意 |
|---|---|---|
| 🌐 **网页版** | 所有人，尤其 iPhone | 不用安装、不会过期、随时是最新版 |
| 🤖 **Android** | Android 手机 | 下载一个文件直接装，不会过期 |
| 🍎 **iPhone 原生版** | 想要完全原生的体验 | 需要电脑操作，**每 7 天要重装一次** |

### 🌐 网页版（最推荐）

用 **Safari** 打开 **[852111.xyz](https://852111.xyz)**，然后添加到主屏幕：

1. 点浏览器右下角的 **「⋯」**
2. 选最上面的 **「分享」**
3. 往下滚，选 **「添加到主屏幕」**
4. 回到主屏幕，从 GameMale 图标打开

添加之后打开没有地址栏、全屏、有自己的图标，用起来就跟一般 App 一样。
第一次打开会多花几秒下载中文字体，之后就不用了。

> **iPhone 为什么推荐这个？** 因为原生 App 用免费的开发者证书签名，Apple 只给 7 天，
> 到期就打不开、要重新安装一次。网页版没有这个问题。

### 🤖 Android 手机

到 **[Releases](../../releases)** 下载 `GameMale.apk`，点开安装即可。
系统会问要不要允许安装来源，同意就好。**不会过期。**

### 🍎 iPhone

原生版需要用电脑侧载，而且**每 7 天要重签一次**（Apple 对免费证书的限制，不是 App 的问题）。

1. 到 **[Releases](../../releases)** 下载 `GameMale.ipa`
2. 用 [Sideloadly](https://sideloadly.io/) 或 [AltStore](https://altstore.io/) 安装
3. 到「设置 → 通用 → VPN 与设备管理」信任你的开发者证书

嫌麻烦的话，**用上面的网页版就好**，功能是一样的。

---

## 功能

<table>
<tr>
<td width="150"><b>📖 浏览</b></td>
<td>版块列表（可展开子版块、点图标看版主与版规）、主题列表可按<b>最新／热门／精华</b>切换，也能只看投票或悬赏。帖子内页支持分页、附件、<b>楼中楼</b>，还能快速跳到指定楼层。</td>
</tr>
<tr>
<td><b>✍️ 发言</b></td>
<td>回复、引用回复、发表新主题、编辑自己的帖子。内置<b>表情选择器</b>与 BBCode 快捷键，回帖有奖励时会直接显示横幅。已经回过的主题会标「已回」。</td>
</tr>
<tr>
<td><b>⭐ 互动</b></td>
<td>评分、投票、顶／踩、收藏主题与版块、使用道具（提升泵／亮色刷）、举报。</td>
</tr>
<tr>
<td><b>📅 每日签到</b></td>
<td>一键签到，看得到<b>排行榜</b>与连续天数。有补签卡可以补签。也可以开「每天自动签到」，每天第一次打开 App 就帮你点好。</td>
</tr>
<tr>
<td><b>💬 私信与提醒</b></td>
<td>私信是<b>气泡对话</b>界面，不是论坛那种列表。新消息与新提醒会在底部显示红点。提醒可以直接回招呼或忽略。</td>
</tr>
<tr>
<td><b>👤 个人空间</b></td>
<td>个人资料（用户组、勋章、管理的版块、加入的群组）、记录广场、日志、相册、好友。可以加好友、打招呼（14 种动作）。</td>
</tr>
<tr>
<td><b>📚 淘帖与群组</b></td>
<td>专辑的推荐／全部／我的，可订阅、评分评论、向作者推荐主题、用标签搜索。自己建的专辑可以编辑、删除、邀请维护。群组能加入／退出／收藏，看得到成员与积分排行。</td>
</tr>
<tr>
<td><b>🔍 搜索</b></td>
<td>帖子、日志、相册、群组、淘帖、用户都能搜，也能只搜本版。<b>单个字也搜得到</b>。高级搜索可指定作者、时间范围与排序。</td>
</tr>
<tr>
<td><b>🎨 个性化</b></td>
<td>深色／浅色主题、<b>彩虹旗六色</b>强调色任选、繁简体即时切换、图片加载策略（一律加载／只在 Wi-Fi／手动）。长按图片可以保存、分享或复制链接。</td>
</tr>
</table>

### 不登录也能用

论坛本身允许游客浏览，App 也一样：**版块、主题、帖子、记录广场、他人资料**不登录就看得到。

回复、发帖、评分、收藏、签到、私信这些要登录才能做——按钮会直接隐藏，不会让你填半天才说不行。

---

## 隐私

这是个人自用项目，不是官方 App，**与 GameMale 官方无关**。

- **不会保存你的密码。** 登录后只留论坛给的 Cookie，跟你用浏览器登录是一样的东西。
- **原生版直连论坛**，账号密码只发送到 `www.gamemale.com`，不经过任何第三方。
- **网页版经过一层转发。** 浏览器有跨域限制，不准网页直接连论坛，所以请求会先经过
  `852111.xyz`（本项目自建的）再发到论坛。**那台服务器不保存任何账号数据**——
  没有数据库、没有你的 Cookie，登录状态完全在你自己的浏览器里。
- **没有任何跟踪、广告或数据收集。**

---

## 常见问题

<details>
<summary><b>网页版和原生 App 有什么差别？</b></summary>

功能完全一样，同一份代码编出来的。差别只在：原生版直连论坛、可以离线缓存图片；
网页版不用安装、不会过期、永远是最新版。iPhone 用户建议直接用网页版。
</details>

<details>
<summary><b>iPhone 版为什么 7 天就打不开？</b></summary>

Apple 对免费开发者证书的限制——用免费账号签的 App 只能跑 7 天。这不是 App 的问题，
所有侧载的 App 都一样。要免除这个限制得付 Apple 每年 99 美金的开发者账号。
**用网页版就没有这个问题。**
</details>

<details>
<summary><b>会不会有推送通知？</b></summary>

没有，而且是刻意拿掉的。原本做过两套（原生后台检查、网页版的推送服务器），
但 iOS 决定何时唤醒 App 的时机完全不可控，实际体验是「该通知时不通知、半夜乱通知」，
而网页版那套还得让服务器保存你的论坛 Cookie。权衡后整套移除了——
**这也是现在能说「服务器不保存任何账号数据」的原因。**
</details>

<details>
<summary><b>图片很吃流量怎么办？</b></summary>

设置 → 流量 → 帖子图片加载，可以选「只在 Wi-Fi 加载」或「手动」。
选手动时图片会先显示占位，点一下才加载。
</details>

<details>
<summary><b>界面可以变繁体吗？</b></summary>

可以，设置里切换，整个界面会立刻重绘。
但**帖子内容一律保留作者原本的用字**——转换过的标题跟论坛上对不起来，找不到帖。
想看转换后的内容，在帖子页上按「翻译」，那是逐篇的。
</details>

---

## 给开发者

架构、技术取舍、以及十几轮实作累积的踩坑笔记在 **[docs/DEVELOPING.md](docs/DEVELOPING.md)**。
网页版后端（论坛转发、图片代理、中文字体处理）在 **[pwa/README.md](pwa/README.md)**。

一句话版本：Flutter 写的，论坛官方手机 API 已关闭，所以解析 `?mobile=2` 的手机版 HTML；
解析层抽成纯 Dart 包 `packages/gm_api`，原生版与网页版后端共用同一份。

```bash
flutter test                                        # 293 项
cd packages/gm_api && dart test                     # 28 项
cd pwa/server && dart test                          # 28 项
```

---

## 授权

个人自用项目。简繁对照数据衍生自 [OpenCC](https://github.com/BYVoid/OpenCC)（Apache-2.0），
用字判断与台湾词汇为本项目自订。

App 图标与论坛内容的版权属于 GameMale 及各自的作者。
