import 'dart:typed_data';

class SessionUser {
  final int? uid;
  final String name;
  final String avatar;
  final bool loggedIn;

  const SessionUser({this.uid, this.name = '', this.avatar = '', this.loggedIn = false});

  Map<String, dynamic> toJson() =>
      {'uid': uid, 'name': name, 'avatar': avatar, 'loggedIn': loggedIn};

  factory SessionUser.fromJson(Map<String, dynamic> j) => SessionUser(
        uid: j['uid'] as int?,
        name: (j['name'] ?? '') as String,
        avatar: (j['avatar'] ?? '') as String,
        loggedIn: (j['loggedIn'] ?? false) as bool,
      );
}

/// 首頁 k_misign 簽到條
class SignInfo {
  final bool signed;
  final String label;
  final String title;
  final int exp;
  final int expMax;
  final double percent;

  /// 滿級：論壇會把上限留空、進度條寫成 width:INF%
  final bool maxed;

  const SignInfo({
    required this.signed,
    required this.label,
    required this.title,
    required this.exp,
    required this.expMax,
    required this.percent,
    this.maxed = false,
  });
}

class ForumItem {
  final int fid;
  final String name;
  final String icon;
  final String threads;
  final String posts;
  final String desc;

  /// 首頁的子版塊藏在簡介裡（「子版块>>」後面那幾個連結）
  final List<SubForum> subforums;

  const ForumItem({
    required this.fid,
    required this.name,
    this.icon = '',
    this.threads = '',
    this.posts = '',
    this.desc = '',
    this.subforums = const [],
  });
}

class ForumGroup {
  final String name;
  final List<ForumItem> forums;
  const ForumGroup({required this.name, required this.forums});
}

class IndexData {
  final List<ForumGroup> groups;
  final SessionUser user;
  final SignInfo? sign;
  const IndexData({required this.groups, required this.user, this.sign});
}

class ThreadItem {
  final int tid;
  final String title;
  final String type;
  final String author;
  final int? uid;
  final String avatar;
  final String date;
  final int views;
  final int replies;
  final String digest;

  /// 只有收藏列表才有，用來取消收藏
  final int? favid;

  /// 版塊名稱（我的主題／回覆那幾頁論壇會給）
  final String forumName;
  final int? fid;

  /// 「我的回覆」才有：我在這帖回了什麼，以及那一樓的 pid
  final String myReply;
  final int? myPid;

  const ThreadItem({
    required this.tid,
    required this.title,
    this.type = '',
    this.author = '',
    this.uid,
    this.avatar = '',
    this.date = '',
    this.views = 0,
    this.replies = 0,
    this.forumName = '',
    this.fid,
    this.myReply = '',
    this.myPid,
    this.digest = '',
    this.favid,
  });
}

class PageInfo {
  final int page;
  final int total;

  /// 有些列表（我的回覆、記錄廣場）只給「上一頁／下一頁」，沒有頁碼，
  /// 這時 total 只是猜的，要靠這兩個旗標決定按鈕能不能按
  final bool hasNext;
  final bool hasPrev;

  /// 論壇有給實際頁碼，頁數選擇器才有意義
  final bool numbered;

  const PageInfo({
    this.page = 1,
    this.total = 1,
    this.hasNext = false,
    this.hasPrev = false,
    this.numbered = true,
  });
}

class ThreadType {
  final int typeid;
  final String name;
  final String count;
  const ThreadType({required this.typeid, required this.name, this.count = ''});
}

class ForumTab {
  final String name;
  final bool cur;
  final String filter;
  final String orderby;
  final bool digest;
  const ForumTab({
    required this.name,
    this.cur = false,
    this.filter = '',
    this.orderby = '',
    this.digest = false,
  });
}

class SubForum {
  final int fid;
  final String name;

  /// 只有「收藏的版塊」才有，用來取消收藏
  final int? favid;
  final String favTime;

  const SubForum({required this.fid, required this.name, this.favid, this.favTime = ''});
}

class ForumData {
  final int fid;
  final String name;
  final List<String> meta;
  final List<SubForum> subforums;
  final List<ThreadType> types;
  final List<ForumTab> tabs;
  final List<ThreadItem> list;
  final PageInfo pager;

  /// 論壇給的提示，例如「抱歉，您没有权限访问该群组」
  final String? message;

  /// 論壇把需要登入的板塊直接轉到登入頁，跟隨轉址後拿到的是登入表單
  final bool requiresLogin;

  const ForumData({
    required this.fid,
    required this.name,
    this.meta = const [],
    this.subforums = const [],
    this.types = const [],
    this.tabs = const [],
    this.list = const [],
    this.pager = const PageInfo(),
    this.message,
    this.requiresLogin = false,
  });
}

class PostItem {
  final int? pid;
  final String floor;
  final String author;
  final int? uid;
  final String avatar;
  final String time;
  final String html;
  final String signature;
  final String quoteHref;
  final List<FloorComment> comments;

  const PostItem({
    this.pid,
    this.floor = '',
    this.author = '',
    this.uid,
    this.avatar = '',
    this.time = '',
    this.html = '',
    this.signature = '',
    this.quoteHref = '',
    this.comments = const [],
  });

  /// 逐篇翻譯用：只換文字，其他照舊
  PostItem mapText(String Function(String) f) => PostItem(
        pid: pid,
        floor: floor,
        author: author,
        uid: uid,
        avatar: avatar,
        time: time,
        html: f(html),
        signature: f(signature),
        quoteHref: quoteHref,
        comments: [
          for (final c in comments)
            FloorComment(
                name: c.name, uid: c.uid, avatar: c.avatar, text: f(c.text)),
        ],
      );
}

class ThreadData {
  final int tid;
  final int? fid;
  final String forumName;
  final String title;
  final String type;
  final List<PostItem> posts;
  final PageInfo pager;
  final Poll? poll;
  final bool requiresLogin;

  const ThreadData({
    required this.tid,
    this.fid,
    this.forumName = '',
    this.title = '',
    this.type = '',
    this.posts = const [],
    this.pager = const PageInfo(),
    this.poll,
    this.requiresLogin = false,
  });
}

class NoticeItem {
  final String id;
  final String avatar;
  final int? uid;
  final String time;
  final String text;
  final int? tid;

  const NoticeItem({
    this.id = '',
    this.avatar = '',
    this.uid,
    this.time = '',
    this.text = '',
    this.tid,
  });
}

class PmItem {
  final int? touid;
  final String name;
  final String last;
  final String time;
  final String avatar;
  final int unread;

  const PmItem({
    this.touid,
    this.name = '',
    this.last = '',
    this.time = '',
    this.avatar = '',
    this.unread = 0,
  });
}

class PmMessage {
  final String html;
  final String text;
  final String avatar;
  final String time;

  /// true = 自己發的，畫面上靠右
  final bool mine;

  const PmMessage({
    this.html = '',
    this.text = '',
    this.avatar = '',
    this.time = '',
    this.mine = false,
  });
}

class PmChat {
  final int touid;
  final String title;
  final List<PmMessage> messages;

  /// 送出時要帶回去的對話 id，沒有就用一般端點
  final String pmid;
  final String formhash;

  const PmChat({
    required this.touid,
    this.title = '',
    this.messages = const [],
    this.pmid = '',
    this.formhash = '',
  });
}

class CreditItem {
  final String name;
  final String value;
  const CreditItem(this.name, this.value);
}

/// 個人資料裡的一個欄位（網名暱稱、生日、居住地…）
/// 勳章。`alt` 是名稱，`tip` 是一段 HTML 說明（含等級與加成效果）
class Medal {
  const Medal({
    required this.image,
    this.name = '',
    this.level = '',
    this.desc = '',
    this.effects = const [],
  });

  final String image;
  final String name;

  /// 「Max」「1」…
  final String level;
  final String desc;

  /// 加成效果，例如「回帖 血液 +1」
  final List<String> effects;
}

class ProfileField {
  final String label;
  final String value;
  const ProfileField(this.label, this.value);
}

/// 個人資料裡的一個連結（管理的版塊、已加入的群組…）
class ProfileLink {
  final String name;
  final int? fid;
  final String url;
  const ProfileLink(this.name, {this.fid, this.url = ''});
}

/// 個人資料的一個區塊。每個人有哪些區塊都不一樣，所以通用解析：
/// 桌面模板全都是 div.pbm + h2 標題 + 內容。
class ProfileSection {
  final String title;
  final List<ProfileLink> links;
  final String text;
  const ProfileSection({required this.title, this.links = const [], this.text = ''});
}

class ProfileData {
  final int uid;
  final String name;
  final String avatar;
  final String level;
  final List<CreditItem> credits;

  /// 是不是自己的頁面（論壇只在自己的頁面放登出鈕）
  final bool isSelf;

  final bool online;
  final List<String> roles;          // 用戶組、擴展角色組
  final List<ProfileField> fields;   // pf_l 的欄位
  final List<ProfileSection> sections;
  final List<Medal> medals;         // 勳章圖網址
  final List<ProfileLink> stats;     // 主題數／回帖數／相冊數…

  const ProfileData({
    required this.uid,
    this.name = '',
    this.avatar = '',
    this.level = '',
    this.credits = const [],
    this.isSelf = false,
    this.online = false,
    this.roles = const [],
    this.fields = const [],
    this.sections = const [],
    this.medals = const [],
    this.stats = const [],
  });
}

class MeData {
  final int uid;
  final String name;
  final String level;
  final String avatar;
  const MeData({required this.uid, this.name = '', this.level = '', this.avatar = ''});
}

class SubmitResult {
  final bool ok;
  final String message;
  const SubmitResult({required this.ok, required this.message});
}

class SecurityQuestion {
  final String id;
  final String name;
  const SecurityQuestion({required this.id, required this.name});
}

class LoginMeta {
  final String formhash;
  final String loginhash;
  final String seccodehash;
  final bool needSeccode;
  final List<SecurityQuestion> questions;
  final Uint8List? seccodeImage;

  const LoginMeta({
    this.formhash = '',
    this.loginhash = '',
    this.seccodehash = '',
    this.needSeccode = false,
    this.questions = const [],
    this.seccodeImage,
  });

  LoginMeta withImage(Uint8List? img) => LoginMeta(
        formhash: formhash,
        loginhash: loginhash,
        seccodehash: seccodehash,
        needSeccode: needSeccode,
        questions: questions,
        seccodeImage: img,
      );
}

class ListPage {
  final List<ThreadItem> list;
  final PageInfo pager;
  final String? message;
  const ListPage({this.list = const [], this.pager = const PageInfo(), this.message});
}

class NewThreadMeta {
  final List<ThreadType> types;
  final bool canPost;
  final String? message;
  const NewThreadMeta({this.types = const [], this.canPost = false, this.message});
}

class SignResult {
  const SignResult({
    this.html = '',
    this.signed = false,
    this.level = '',
    this.stats = const [],
  });

  /// 論壇給的整段 HTML，只在解不出結構化欄位時當備案
  final String html;
  final bool signed;

  /// 「簽到等級 Lv 12」
  final String level;

  /// 今日排名／連續簽到／累計簽到
  final List<({String label, String value})> stats;
}

class NoticeResult {
  final List<NoticeItem> items;
  final String? message;
  const NoticeResult({this.items = const [], this.message});
}

class PmListResult {
  final List<PmItem> items;
  final String? message;
  const PmListResult({this.items = const [], this.message});
}

/// 論壇回應 4xx/5xx 或連不上時丟這個，UI 直接顯示 message
class DiscuzException implements Exception {
  final String message;
  final int status;
  const DiscuzException(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

/// 發文後論壇給的積分變化（勳章觸發也走同一套）
class CreditChange {
  final String name;
  final int delta;
  final String unit;
  const CreditChange(this.name, this.delta, this.unit);

  @override
  String toString() => '$name ${delta > 0 ? '+' : ''}$delta$unit';
}

/// 記錄底下的一則回覆
class DoingComment {
  const DoingComment({
    required this.cid,
    this.author = '',
    this.uid,
    this.text = '',
    this.time = '',
    this.deleteUrl = '',
  });

  final int cid;
  final String author;
  final int? uid;
  final String text;
  final String time;

  /// 只有自己的記錄／自己的回覆才有
  final String deleteUrl;
}

class DoingItem {
  final int doid;
  final int? uid;
  final String name;
  final String avatar;

  /// 已淨化的 HTML —— 記錄裡會夾表情圖，純文字會把它們吃掉
  final String html;
  final String message;
  final String time;
  final List<DoingComment> comments;

  /// 自己的記錄才有
  final String deleteUrl;

  const DoingItem({
    required this.doid,
    this.uid,
    this.name = '',
    this.avatar = '',
    this.html = '',
    this.message = '',
    this.time = '',
    this.comments = const [],
    this.deleteUrl = '',
  });
}

class DoingPage {
  final List<DoingItem> items;
  final String formhash;
  final PageInfo pager;
  const DoingPage({
    this.items = const [],
    this.formhash = '',
    this.pager = const PageInfo(),
  });
}

class PollOption {
  final String id;
  final String text;

  /// 已經投過票時論壇會把結果一起給出來
  final String percent;
  final int votes;

  const PollOption(this.id, this.text, {this.percent = '', this.votes = 0});
}

class Poll {
  final String title;      // 单选投票 / 多选投票
  final String info;       // 共有 N 人参与投票…
  final String deadline;
  final List<PollOption> options;
  final bool multiple;
  final String formhash;
  final String action;

  /// 論壇給的狀態句，例如「您已经投过票，谢谢您的参与」
  final String status;

  /// 有沒有可以送出的表單。已經投過票時論壇只給結果，不給 radio
  bool get votable => options.any((o) => o.id.isNotEmpty);

  /// 已經投過票（論壇改成顯示百分比與票數）
  bool get voted => !votable && options.isNotEmpty;

  const Poll({
    this.title = '',
    this.info = '',
    this.deadline = '',
    this.status = '',
    this.options = const [],
    this.multiple = false,
    this.formhash = '',
    this.action = '',
  });
}

/// 樓中樓（dxksst 外掛）
class FloorComment {
  final int? uid;
  final String name;
  final String avatar;
  final String text;
  const FloorComment({this.uid, this.name = '', this.avatar = '', this.text = ''});
}

/// 評分表單裡的一個積分項。
///
/// 論壇會依使用者等級決定給哪些項目 —— 低等級帳號可能只有「追随」，
/// 所以送出時只能帶回實際存在的項目，硬塞不存在的會卡住。
class RateOption {
  final String field;        // score3 / score4 / score8
  final String name;         // 血液 / 追随 / 堕落
  final List<int> choices;   // 論壇允許的加分值
  final String range;        // 0 ~ 3
  final String remaining;    // 今日剩餘
  const RateOption({
    required this.field,
    required this.name,
    this.choices = const [],
    this.range = '',
    this.remaining = '',
  });
}

class RateForm {
  final List<RateOption> options;
  final List<String> reasons;
  final String formhash;
  final String tid;
  final String pid;
  final String referer;
  final String? message;    // 不能評分時論壇給的說明

  bool get canRate => options.isNotEmpty;

  const RateForm({
    this.options = const [],
    this.reasons = const [],
    this.formhash = '',
    this.tid = '',
    this.pid = '',
    this.referer = '',
    this.message,
  });
}

class RateRecord {
  /// 同一次評分可能同時給多項積分，論壇是拆成多列回傳的，這裡合併成一筆
  final List<String> credits;   // ['血液 +2 滴', '追随 +1 人']
  final String name;
  final int? uid;
  final String time;
  final String reason;

  const RateRecord({
    this.credits = const [],
    this.name = '',
    this.uid,
    this.time = '',
    this.reason = '',
  });
}

/// 編輯自己的帖子／回覆
class EditForm {
  final String subject;   // 只有樓主那層有標題
  final String message;   // 原始 BBCode
  final String formhash;
  final String posttime;
  final String fid;
  final String tid;
  final String pid;
  final bool hasSubject;
  final String? message2;  // 論壇的提示（沒權限時）

  const EditForm({
    this.subject = '',
    this.message = '',
    this.formhash = '',
    this.posttime = '',
    this.fid = '',
    this.tid = '',
    this.pid = '',
    this.hasSubject = false,
    this.message2,
  });

  bool get canEdit => formhash.isNotEmpty && pid.isNotEmpty;
}

/// 搜尋的分類。日誌／相簿／群組／使用者都沒有手機版，
/// 靠 Api.get 自動跟進「無手機頁面」提示才拿得到內容。
enum SearchScope {
  forum('帖子', 'forum'),
  blog('日誌', 'blog'),
  album('相簿', 'album'),
  group('群組', 'group'),
  user('使用者', 'user');

  const SearchScope(this.label, this.mod);
  final String label;
  final String mod;
}

/// 一筆搜尋結果（各分類共用）
class SearchHit {
  final String title;
  final String subtitle;
  final String image;
  final int? tid;
  final int? uid;
  final int? fid;

  /// 站外或站內都可能，點擊時由 UI 決定怎麼開
  final String url;

  const SearchHit({
    required this.title,
    this.subtitle = '',
    this.image = '',
    this.tid,
    this.uid,
    this.fid,
    this.url = '',
  });
}

class SearchResult {
  final List<SearchHit> hits;
  final String summary;
  final PageInfo pager;
  final String? message;
  const SearchResult({
    this.hits = const [],
    this.summary = '',
    this.pager = const PageInfo(),
    this.message,
  });
}

/// 個人空間的子頁。這站這些頁面只有桌面模板
enum SpaceTab {
  home('空間首頁', 'index', ''),
  doing('記錄', 'doing', 'me'),
  blog('日誌', 'blog', 'me'),
  album('相冊', 'album', 'me'),
  thread('主題', 'thread', 'me'),
  wall('留言板', 'wall', ''),
  friend('好友', 'friend', 'me');

  const SpaceTab(this.label, this.action, this.view);
  final String label;
  final String action;
  final String view;
}

/// 空間裡的一列。七個子頁版型差很多，共用一個寬鬆的型別，用得到才填
class SpaceItem {
  const SpaceItem({
    this.title = '',
    this.body = '',
    this.meta = '',
    this.author = '',
    this.date = '',
    this.image = '',
    this.avatar = '',
    this.url = '',
    this.uid,
    this.tid,
    this.fid,
    this.albumId,
    this.children = const [],
    this.locked = false,
    this.actions = const {},
  });

  final String title;
  final String body;

  /// 附註：日誌的閱讀數、主題的版塊與回覆數、相冊的張數
  final String meta;
  final String author;
  final String date;
  final String image;
  final String avatar;
  final String url;
  final int? uid;
  final int? tid;
  final int? fid;
  final int? albumId;

  /// 記錄的回覆，或空間首頁裡一個區塊的內容
  final List<SpaceItem> children;

  /// 相冊沒公開時封面是 nopublish.gif
  final bool locked;

  /// 這一項可以做什麼：編輯／刪除／置頂 → 論壇給的連結
  final Map<String, String> actions;
}

class SpaceData {
  const SpaceData({
    required this.tab,
    this.owner = '',
    this.items = const [],
    this.pager = const PageInfo(),
    this.formhash = '',
    this.message,
    this.needsLogin = false,
    this.restricted = false,
  });

  final SpaceTab tab;
  final String owner;
  final List<SpaceItem> items;
  final PageInfo pager;
  final String formhash;

  /// 空的時候要說明為什麼空（沒東西／被鎖／要登入）
  final String? message;

  /// 論壇把我們轉去登入頁了
  final bool needsLogin;

  /// 對方的隱私設定擋住了
  final bool restricted;
}

/// 回帖獎勵：`pool` 是獎池餘額（13783 枚金幣），`rule` 是規則說明
class ThreadPrize {
  const ThreadPrize({required this.pool, required this.rule});
  final String pool;
  final String rule;
}

/// 註冊問答的一個選項
class QuizOption {
  const QuizOption({required this.value, required this.label});
  final String value;
  final String label;
}

/// 註冊問答的一題。`multi` 是複選（表單欄位名字結尾是 `[]`）
class QuizQuestion {
  const QuizQuestion({
    required this.field,
    required this.title,
    required this.options,
    required this.multi,
  });

  final String field;
  final String title;
  final List<QuizOption> options;
  final bool multi;
}

/// 註冊問答頁（plugin.php?id=k_qareg:k_qareg）。
/// `notice` 是頁面頂端那行字，論壇關閉註冊時會寫在這裡
class RegisterQuiz {
  const RegisterQuiz({
    this.notice = '',
    this.formhash = '',
    this.questions = const [],
    this.closed = false,
  });

  final String notice;
  final String formhash;
  final List<QuizQuestion> questions;

  /// 論壇是否關閉註冊
  final bool closed;
}

/// 版塊列表的篩選條件。Discuz 的 `filter` 只能有一個值，
/// 但 `specialtype`／`dateline`／`orderby` 可以疊在上面（實測過）
class ForumQuery {
  const ForumQuery({
    this.special = '',
    this.tab = '',
    this.orderby = '',
    this.dateline = 0,
    this.typeid = 0,
  });

  /// '' | poll | reward
  final String special;

  /// '' | lastpost | heat | hot | digest
  final String tab;

  /// '' | dateline（發帖時間）| replies（回覆數）| views（查看數）
  final String orderby;

  /// 秒數：86400 一天、604800 一週…
  final int dateline;

  /// 主題分類
  final int typeid;

  ForumQuery copyWith({
    String? special,
    String? tab,
    String? orderby,
    int? dateline,
    int? typeid,
  }) =>
      ForumQuery(
        special: special ?? this.special,
        tab: tab ?? this.tab,
        orderby: orderby ?? this.orderby,
        dateline: dateline ?? this.dateline,
        typeid: typeid ?? this.typeid,
      );

  bool get isDefault =>
      special.isEmpty &&
      tab.isEmpty &&
      orderby.isEmpty &&
      dateline == 0 &&
      typeid == 0;

  /// 有沒有動到「更多」裡的東西，決定那顆按鈕要不要亮起來
  bool get hasExtra => orderby.isNotEmpty || dateline > 0;

  /// 組成 forum.php 的查詢參數
  Map<String, String> toParams() {
    final q = <String, String>{};

    if (typeid > 0) {
      q['filter'] = 'typeid';
      q['typeid'] = '$typeid';
    } else if (special.isNotEmpty) {
      q['filter'] = 'specialtype';
      q['specialtype'] = special;
    } else if (dateline > 0) {
      q['filter'] = 'dateline';
    } else if (orderby.isNotEmpty) {
      // 發帖時間走 author，回覆／查看走 reply —— 論壇自己就是這樣分的
      q['filter'] = orderby == 'dateline' ? 'author' : 'reply';
    } else if (tab.isNotEmpty) {
      q['filter'] = tab;
    }

    if (dateline > 0) q['dateline'] = '$dateline';
    if (tab == 'digest') q['digest'] = '1';

    final order = orderby.isNotEmpty
        ? orderby
        : switch (tab) {
            'lastpost' => 'lastpost',
            'heat' => 'heats',
            _ => '',
          };
    if (order.isNotEmpty) q['orderby'] = order;

    return q;
  }
}

/// 「更多」裡的排序選項
const forumOrderOptions = <({String value, String label})>[
  (value: '', label: '預設'),
  (value: 'dateline', label: '發帖時間'),
  (value: 'replies', label: '回覆/查看'),
  (value: 'views', label: '查看'),
];

/// 「更多」裡的時間範圍
const forumDateOptions = <({int value, String label})>[
  (value: 0, label: '全部時間'),
  (value: 86400, label: '一天'),
  (value: 172800, label: '兩天'),
  (value: 604800, label: '一週'),
  (value: 2592000, label: '一個月'),
  (value: 7948800, label: '三個月'),
];

/// 主題類別
const forumSpecialOptions = <({String value, String label})>[
  (value: '', label: '全部主題'),
  (value: 'poll', label: '投票'),
  (value: 'reward', label: '懸賞'),
];

/// 帖子附件。免費的 `url` 直接可下載；要付費的 `price` 有值，`url` 是購買頁
class Attachment {
  const Attachment({
    required this.name,
    required this.url,
    this.icon = '',
    this.info = '',
    this.price = '',
    this.permission = '',
    this.recordUrl = '',
    this.bought = false,
  });

  final String name;

  /// 已買（或免費）時是下載網址，否則是購買頁
  final String url;
  final String icon;

  /// 「223 Bytes, 下载次数: 27」
  final String info;

  /// 「2 枚金币」，免費的話是空字串
  final String price;

  /// 「阅读权限: 15」
  final String permission;

  /// 購買紀錄頁
  final String recordUrl;

  /// 已經買過（或本來就免費）—— 論壇這時把連結換成 mod=attachment 直接下載
  final bool bought;

  /// 要花錢，而且還沒買
  bool get needsPay => price.isNotEmpty && !bought;

  /// 購買頁網址裡的附件 id
  int? get aid => int.tryParse(
      RegExp(r'[?&]aid=(\d+)').firstMatch(url)?.group(1) ?? '');
}

/// 購買附件的確認資訊
class AttachPay {
  const AttachPay({
    this.name = '',
    this.author = '',
    this.rows = const [],
    this.formhash = '',
    this.action = '',
    this.aid = '',
    this.message,
  });

  final String name;
  final String author;

  /// 售價／作者所得／購買後餘額，論壇給幾列就顯示幾列
  final List<({String label, String value})> rows;

  final String formhash;
  final String action;
  final String aid;

  /// 拿不到表單時的原因
  final String? message;

  bool get ready => formhash.isNotEmpty && action.isNotEmpty;
}

/// 帖子頁桌面模板才有的東西：回帖獎勵與附件清單
class ThreadExtras {
  const ThreadExtras({this.prize, this.attachments = const []});
  final ThreadPrize? prize;
  final List<Attachment> attachments;

  bool get isEmpty => prize == null && attachments.isEmpty;
}

/// 相冊內頁
class AlbumData {
  const AlbumData({
    this.title = '',
    this.count = '',
    this.photos = const [],
    this.pager = const PageInfo(),
    this.message,
  });

  final String title;
  final String count;
  final List<AlbumPhoto> photos;
  final PageInfo pager;
  final String? message;
}

class AlbumPhoto {
  const AlbumPhoto({required this.thumb, required this.full, this.picid});
  final String thumb;
  final String full;
  final int? picid;
}

/// 日誌的表態按鈕（震驚／感謝／關心／加油／有愛）
class BlogReaction {
  const BlogReaction({
    required this.name,
    required this.count,
    this.icon = '',
    this.url = '',
  });

  final String name;
  final int count;
  final String icon;

  /// 表態的連結，裡面帶著 clickid 與 hash，按下去就是送出
  final String url;
}

/// 日誌的一則評論
class BlogComment {
  const BlogComment({
    required this.author,
    this.uid,
    this.avatar = '',
    this.date = '',
    this.text = '',
    this.quote = '',
    this.editUrl = '',
    this.deleteUrl = '',
  });

  final String author;
  final int? uid;
  final String avatar;
  final String date;
  final String text;

  /// 回覆別人時引用的那段
  final String quote;

  /// 自己的評論（或自己日誌底下的評論）才有
  final String editUrl;
  final String deleteUrl;
}

/// 日誌內頁
class BlogData {
  const BlogData({
    this.title = '',
    this.author = '',
    this.meta = '',
    this.html = '',
    this.reactions = const [],
    this.reactedBy = const [],
    this.reactedCount = '',
    this.comments = const [],
    this.otherPosts = const [],
    this.formhash = '',
    this.editUrl = '',
    this.deleteUrl = '',
    this.stickUrl = '',
    this.favoriteUrl = '',
    this.stats = const [],
    this.message,
  });

  final String title;
  final String author;
  final String meta;

  /// 已淨化過的內文 HTML
  final String html;

  final List<BlogReaction> reactions;

  /// 剛表態過的朋友
  final List<SpaceItem> reactedBy;
  final String reactedCount;

  final List<BlogComment> comments;

  /// 作者的其他最新日誌
  final List<SpaceItem> otherPosts;

  final String formhash;

  /// 自己的日誌才有：編輯／刪除／置頂
  final String editUrl;
  final String deleteUrl;
  final String stickUrl;

  /// 收藏這篇日誌
  final String favoriteUrl;

  /// 「熱度 142」「已有 328 次閱讀」「2026-8-24 21:06」「系統分類:論壇話題」
  final List<({String label, String value})> stats;

  final String? message;
}

/// 帖子高級搜索的完整選項，對應 search.php?mod=forum&adv=yes
class AdvancedSearch {
  const AdvancedSearch({
    this.fulltext = false,
    this.author = '',
    this.scope = 'all',
    this.special = const {},
    this.srchfrom = 0,
    this.before = false,
    this.orderby = 'lastpost',
    this.ascending = false,
    this.forums = const {},
  });

  /// 勾了就連內文一起搜，不只標題
  final bool fulltext;

  /// 只搜這個作者
  final String author;

  /// all / digest / top
  final String scope;

  /// 特殊主題：1 投票、2 商品、3 懸賞、4 活動、5 辯論
  final Set<int> special;

  /// 秒數，0 = 全部時間
  final int srchfrom;

  /// true = 該時間「以前」，false = 「以內」
  final bool before;

  /// lastpost / dateline / replies / views
  final String orderby;
  final bool ascending;

  /// 搜尋範圍：要搜哪幾個版塊，空的代表全部版塊
  final Set<int> forums;

  AdvancedSearch copyWith({
    bool? fulltext,
    String? author,
    String? scope,
    Set<int>? special,
    int? srchfrom,
    bool? before,
    String? orderby,
    bool? ascending,
    Set<int>? forums,
  }) =>
      AdvancedSearch(
        fulltext: fulltext ?? this.fulltext,
        author: author ?? this.author,
        scope: scope ?? this.scope,
        special: special ?? this.special,
        srchfrom: srchfrom ?? this.srchfrom,
        before: before ?? this.before,
        orderby: orderby ?? this.orderby,
        ascending: ascending ?? this.ascending,
        forums: forums ?? this.forums,
      );

  bool get isDefault =>
      !fulltext &&
      author.isEmpty &&
      scope == 'all' &&
      special.isEmpty &&
      srchfrom == 0 &&
      orderby == 'lastpost' &&
      !ascending &&
      forums.isEmpty;

  /// 論壇的表單欄位名。special 是陣列，交給呼叫端展開
  Map<String, String> toParams() => {
        if (fulltext) 'srchtype': 'fulltext',
        if (author.isNotEmpty) 'srchuname': author,
        'srchfilter': scope,
        if (srchfrom > 0) 'srchfrom': '$srchfrom',
        if (srchfrom > 0) 'before': before ? '1' : '',
        'orderby': orderby,
        'ascdesc': ascending ? 'asc' : 'desc',
      };
}

const searchTimeOptions = <({int value, String label})>[
  (value: 0, label: '全部時間'),
  (value: 86400, label: '一天'),
  (value: 172800, label: '兩天'),
  (value: 604800, label: '一週'),
  (value: 2592000, label: '一個月'),
  (value: 7776000, label: '三個月'),
  (value: 15552000, label: '半年'),
  (value: 31536000, label: '一年'),
];

const searchOrderOptions = <({String value, String label})>[
  (value: 'lastpost', label: '回覆時間'),
  (value: 'dateline', label: '發表時間'),
  (value: 'replies', label: '回覆數量'),
  (value: 'views', label: '瀏覽次數'),
];

const searchScopeOptions = <({String value, String label})>[
  (value: 'all', label: '全部主題'),
  (value: 'digest', label: '精華主題'),
  (value: 'top', label: '置頂主題'),
];

const searchSpecialOptions = <({int value, String label})>[
  (value: 1, label: '投票'),
  (value: 2, label: '商品'),
  (value: 3, label: '懸賞'),
  (value: 4, label: '活動'),
  (value: 5, label: '辯論'),
];

/// 群組列表的一項
class GroupItem {
  const GroupItem({required this.fid, required this.name, this.icon = ''});
  final int fid;
  final String name;
  final String icon;
}

/// 群組內頁
class GroupData {
  const GroupData({
    this.fid = 0,
    this.name = '',
    this.icon = '',
    this.desc = '',
    this.meta = '',
    this.threads = const [],
    this.pager = const PageInfo(),
    this.canJoin = false,
    this.needsLogin = false,
    this.message,
  });

  final int fid;
  final String name;
  final String icon;
  final String desc;

  /// 群組等級、積分、群主
  final String meta;

  final List<ThreadItem> threads;
  final PageInfo pager;

  /// 還沒加入，論壇只給介紹跟一顆「加入群組」
  final bool canJoin;
  final bool needsLogin;
  final String? message;
}

/// 日誌廣場的三種視角，跟記錄廣場同一套
const blogViews = <({String key, String name, bool needsLogin})>[
  (key: 'all', name: '隨便看看', needsLogin: false),
  (key: 'we', name: '好友的日誌', needsLogin: true),
  (key: 'me', name: '我的日誌', needsLogin: true),
];

/// 日誌分類（論壇自己列出來的）
class BlogCategory {
  const BlogCategory({required this.catid, required this.name});
  final int catid;
  final String name;
}

class BlogListPage {
  const BlogListPage({
    this.items = const [],
    this.categories = const [],
    this.pager = const PageInfo(),
    this.needsLogin = false,
    this.message,
  });

  final List<SpaceItem> items;
  final List<BlogCategory> categories;
  final PageInfo pager;
  final bool needsLogin;
  final String? message;
}

/// 簽到說明頁的一張表
class SignRuleTable {
  const SignRuleTable({this.title = '', this.rows = const []});
  final String title;

  /// 每一列已經去掉論壇那個空的圖示欄
  final List<List<String>> rows;
}

class SignRules {
  const SignRules({this.intro = '', this.tables = const [], this.text = ''});

  /// 「基础奖励: 3~3 枚金币」
  final String intro;
  final List<SignRuleTable> tables;

  /// 沒有表格的頁面（道具擴展）就只有一段文字
  final String text;
}

const signRulePages = <({String op, String name})>[
  (op: 'rewardrule', name: '獎勵規則'),
  (op: 'leval', name: '簽到等級'),
  (op: 'magics', name: '道具擴展'),
];
