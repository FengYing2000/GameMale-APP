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

  const ForumItem({
    required this.fid,
    required this.name,
    this.icon = '',
    this.threads = '',
    this.posts = '',
    this.desc = '',
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
    this.digest = '',
    this.favid,
  });
}

class PageInfo {
  final int page;
  final int total;
  const PageInfo({this.page = 1, this.total = 1});
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
  const Medal({required this.image, this.name = '', this.desc = ''});
  final String image;
  final String name;
  final String desc;
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
  final String html;
  final bool signed;
  const SignResult({this.html = '', this.signed = false});
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

class DoingItem {
  final int doid;
  final int? uid;
  final String name;
  final String avatar;
  final String message;
  final String time;

  const DoingItem({
    required this.doid,
    this.uid,
    this.name = '',
    this.avatar = '',
    this.message = '',
    this.time = '',
  });
}

class DoingPage {
  final List<DoingItem> items;
  final String formhash;
  const DoingPage({this.items = const [], this.formhash = ''});
}

class PollOption {
  final String id;
  final String text;
  const PollOption(this.id, this.text);
}

class Poll {
  final String title;      // 单选投票 / 多选投票
  final String info;       // 共有 N 人参与投票…
  final String deadline;
  final List<PollOption> options;
  final bool multiple;
  final String formhash;
  final String action;

  /// 已經投過或結果已公開時，論壇不再給選項
  bool get votable => options.isNotEmpty;

  const Poll({
    this.title = '',
    this.info = '',
    this.deadline = '',
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
}

class SpaceData {
  const SpaceData({
    required this.tab,
    this.owner = '',
    this.items = const [],
    this.pager = const PageInfo(),
    this.formhash = '',
    this.message,
  });

  final SpaceTab tab;
  final String owner;
  final List<SpaceItem> items;
  final PageInfo pager;
  final String formhash;

  /// 空的時候要說明為什麼空（沒東西／被鎖／要登入）
  final String? message;
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
  });

  final String name;
  final String url;
  final String icon;

  /// 「223 Bytes, 下载次数: 27」
  final String info;

  /// 「2 枚金币」，免費的話是空字串
  final String price;

  bool get needsPay => price.isNotEmpty;
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

/// 日誌內頁
class BlogData {
  const BlogData({
    this.title = '',
    this.author = '',
    this.meta = '',
    this.html = '',
    this.message,
  });

  final String title;
  final String author;
  final String meta;

  /// 已淨化過的內文 HTML
  final String html;
  final String? message;
}
