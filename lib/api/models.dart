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

  const ForumData({
    required this.fid,
    required this.name,
    this.meta = const [],
    this.subforums = const [],
    this.types = const [],
    this.tabs = const [],
    this.list = const [],
    this.pager = const PageInfo(),
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

  const ThreadData({
    required this.tid,
    this.fid,
    this.forumName = '',
    this.title = '',
    this.type = '',
    this.posts = const [],
    this.pager = const PageInfo(),
    this.poll,
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

class ProfileData {
  final int uid;
  final String name;
  final String avatar;
  final String level;
  final List<CreditItem> credits;

  /// 是不是自己的頁面（論壇只在自己的頁面放登出鈕）
  final bool isSelf;

  const ProfileData({
    required this.uid,
    this.name = '',
    this.avatar = '',
    this.level = '',
    this.credits = const [],
    this.isSelf = false,
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
