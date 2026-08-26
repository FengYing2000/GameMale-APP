import '../../i18n/ui.dart';
import '../widgets/require_login.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/http.dart';
import '../../api/models.dart';
import '../../store/session.dart';
import '../../store/settings.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/quick_menu.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  IndexData? _data;
  List<SubForum> _favForums = const [];
  List<CollectionItem> _collections = const [];
  bool _loading = true;
  bool _signing = false;
  String? _err;
  final _open = <int, bool>{};

  /// 哪些版塊的子版塊被展開了
  final _openSubs = <int, bool>{};

  /// fid → 子版塊，來自桌面首頁
  Map<int, List<SubForum>> _subforums = const {};

  /// fid → 版主名單，來自桌面首頁
  Map<int, List<String>> _moderators = const {};


  int _rev = -1;
  int _langTick = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 登入/登出後這個分頁還被保活著，靠 revision 判斷要不要重抓。
    // 第一次只記錄不重抓 —— initState 已經載過了，否則每次開頁都會抓兩遍
    final rev = context.watch<SessionStore>().revision;
    final lang = context.watch<SettingsStore>().langTick.value;
    if (_rev == -1) {
      _rev = rev;
      _langTick = lang;
      return;
    }
    // 版塊名走 sys()，語言換了要重抓才會跟著變
    if (_rev != rev || _langTick != lang) {
      _rev = rev;
      _langTick = lang;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final r = await api.fetchIndex();
      if (!mounted) return;
      context.read<SessionStore>().setSign(r.sign);
      if (r.user.loggedIn) context.read<SessionStore>().applyUser(r.user);
      setState(() {
        _data = r;
        for (var i = 0; i < r.groups.length; i++) {
          _open.putIfAbsent(i, () => true);
        }
      });
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    _loadFavorites();
    _loadSubforums();
    _loadCollections();
  }

  /// 我訂閱的專輯（淘帖）。只有桌面模板，登入了才有東西
  Future<void> _loadCollections() async {
    if (!mounted) return;
    if (context.read<SessionStore>().uid == null) {
      if (_collections.isNotEmpty) setState(() => _collections = const []);
      return;
    }
    try {
      final c = await api.fetchCollections();
      if (mounted) setState(() => _collections = c);
    } on DiscuzException {
      // 抓不到就不顯示這一區
    }
  }

  /// 手機模板的子版塊列不齊（勳章公會的「勳章博物館」就漏了），
  /// 桌面首頁才完整。gzip 約 35 KB，一個 App 生命週期只抓一次
  Future<void> _loadSubforums() async {
    try {
      final map = await api.fetchIndexSubforums();
      final mods = await api.fetchIndexModerators();
      if (!mounted) return;
      setState(() {
        if (map.isNotEmpty) _subforums = map;
        if (mods.isNotEmpty) _moderators = mods;
      });
    } on DiscuzException {
      // 抓不到就用手機版列到的那些
    }
  }

  /// 收藏的版塊是另一支端點（約 8 KB），登入了才有意義
  Future<void> _loadFavorites() async {
    if (!mounted) return;
    final uid = context.read<SessionStore>().uid;
    if (uid == null) {
      if (_favForums.isNotEmpty) setState(() => _favForums = const []);
      return;
    }
    try {
      final f = await api.fetchFavoriteForums(uid);
      if (mounted) setState(() => _favForums = f);
    } on DiscuzException {
      // 抓不到就不顯示，不用打擾使用者
    }
  }

  Future<void> _sign() async {
    if (_signing || (_data?.sign?.signed ?? false)) return;
    if (!await requireLogin(context, action: tr('簽到'))) return;
    if (!mounted) return;
    setState(() => _signing = true);
    try {
      final r = await api.doSign();
      if (mounted) toast(context, r.message);
      if (r.ok) await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('簽到失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _signing = false);
    }
  }

  /// 兩邊都可能漏：手機首頁少了勳章公會那種，桌面首頁只展開部分分類。
  /// 取聯集才齊全
  List<SubForum> _subsOf(ForumItem f) {
    final extra = _subforums[f.fid];
    if (extra == null || extra.isEmpty) return f.subforums;
    final out = [...f.subforums];
    for (final s in extra) {
      if (out.any((x) => x.fid == s.fid)) continue;
      out.add(s);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    final data = _data;

    return Scaffold(
      drawer: const QuickDrawer(),
      appBar: AppBar(
        title: const Text('GameMale'),
        leading: Builder(
          builder: (c) => Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Avatar(session.avatar,
                size: 30, onTap: () => Scaffold.of(c).openDrawer()),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.bell),
            tooltip: tr('通知'),
            onPressed: () => context.push('/notice'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (data != null) ...[
              if (data.sign case final sign?) _SignCard(
                  sign: sign, busy: _signing, onSign: _sign),
              if (_collections.isNotEmpty) _Collections(items: _collections),
              if (_favForums.isNotEmpty) _FavoriteForums(items: _favForums),
              for (var i = 0; i < data.groups.length; i++) ...[
                _GroupHeader(
                  name: data.groups[i].name,
                  open: _open[i] ?? true,
                  onTap: () => setState(() => _open[i] = !(_open[i] ?? true)),
                ),
                if (_open[i] ?? true)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var j = 0; j < data.groups[i].forums.length; j++) ...[
                          _ForumRow(
                            item: data.groups[i].forums[j],
                            subforums: _subsOf(data.groups[i].forums[j]),
                            moderators:
                                _moderators[data.groups[i].forums[j].fid] ??
                                    data.groups[i].forums[j].moderators,
                            expanded:
                                _openSubs[data.groups[i].forums[j].fid] ?? false,
                            onToggle: () => setState(() {
                              final fid = data.groups[i].forums[j].fid;
                              _openSubs[fid] = !(_openSubs[fid] ?? false);
                            }),
                          ),
                          if (_openSubs[data.groups[i].forums[j].fid] ?? false) ...[
                            _ForumExpanded(
                              item: data.groups[i].forums[j],
                              moderators:
                                  _moderators[data.groups[i].forums[j].fid] ??
                                      data.groups[i].forums[j].moderators,
                            ),
                            for (final sub in _subsOf(data.groups[i].forums[j]))
                              _SubForumRow(item: sub),
                          ],
                          if (j != data.groups[i].forums.length - 1)
                            const Divider(indent: 66, endIndent: 14),
                        ],
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SignCard extends StatelessWidget {
  const _SignCard({required this.sign, required this.busy, required this.onSign});
  final SignInfo sign;
  final bool busy;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(sign.title.isEmpty ? tr('等級') : sign.title,
                          style: TextStyle(fontSize: 12.5, color: subtle(context))),
                      Text(
                          sign.maxed
                              ? '${sign.exp} · 已滿級'
                              : '${sign.exp} / ${sign.expMax}',
                          style: TextStyle(fontSize: 12.5, color: faint(context))),
                    ],
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (sign.percent / 100).clamp(0.0, 1.0),
                      minHeight: 7,
                      backgroundColor:
                          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.07),
                      valueColor: const AlwaysStoppedAnimation(brand),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            sign.signed
                ? OutlinedButton(onPressed: null, child: Text(busy ? '…' : tr('已簽到')))
                : FilledButton(onPressed: busy ? null : onSign, child: Text(busy ? '…' : tr('簽到'))),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name, required this.open, required this.onTap});
  final String name;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(name,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: faint(context))),
            Icon(open ? LucideIcons.chevronDown : LucideIcons.chevronRight,
                size: 18, color: faint(context)),
          ],
        ),
      ),
    );
  }
}

/// 我訂閱的專輯
class _Collections extends StatelessWidget {
  const _Collections({required this.items});
  final List<CollectionItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          child: Text(tr('我訂閱的專輯'),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: faint(context))),
        ),
        SizedBox(
          height: 92,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final c in items)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: SizedBox(
                    width: 190,
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => context.push('/collection/${c.ctid}'),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(LucideIcons.library,
                                      size: 15,
                                      color:
                                          Theme.of(context).colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(c.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${c.threads} ${tr('主題')}'
                                '${c.meta.isEmpty ? '' : '　${c.meta}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: faint(context)),
                              ),
                              const Spacer(),
                              if (c.latest.isNotEmpty)
                                Text(c.latest,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: subtle(context))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 收藏的版塊擺在最前面，一排橫向捷徑
class _FavoriteForums extends StatelessWidget {
  const _FavoriteForums({required this.items});
  final List<SubForum> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
          child: Text(tr('我收藏的版塊'),
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: faint(context))),
        ),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final f in items)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(LucideIcons.star, size: 15),
                    label: Text(f.name, style: const TextStyle(fontSize: 13)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.push('/f/${f.fid}'),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 展開後列在母版塊底下
class _SubForumRow extends StatelessWidget {
  const _SubForumRow({required this.item});
  final SubForum item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/f/${item.fid}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(66, 9, 14, 9),
        child: Row(
          children: [
            if (item.icon.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: CachedNetworkImage(
                  imageUrl: item.icon,
                  httpHeaders: Api.imageHeaders,
                  width: 26,
                  height: 20,
                  fit: BoxFit.cover,
                  errorWidget: (c, _, _) =>
                      Icon(LucideIcons.cornerDownRight, size: 15, color: faint(c)),
                ),
              )
            else
              Icon(LucideIcons.cornerDownRight, size: 15, color: faint(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(item.name,
                  style: TextStyle(fontSize: 14, color: subtle(context))),
            ),
            Icon(LucideIcons.chevronRight, size: 16, color: faint(context)),
          ],
        ),
      ),
    );
  }
}

class _ForumRow extends StatelessWidget {
  const _ForumRow({
    required this.item,
    this.subforums = const [],
    this.moderators = const [],
    this.expanded = false,
    this.onToggle,
  });
  final ForumItem item;
  final List<SubForum> subforums;
  final List<String> moderators;
  final bool expanded;
  final VoidCallback? onToggle;

  /// 41412 → 4.1萬，讓回覆數不要一長串
  static String _short(String raw) {
    final n = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    if (n == null) return raw;
    if (n >= 10000) {
      final w = n / 10000;
      return '${w.toStringAsFixed(w >= 100 ? 0 : 1)}萬';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    // 有子版塊、簡介或版主，就給一顆展開鈕把它們收起來，別擠在列表裡
    final canExpand =
        subforums.isNotEmpty || item.desc.isNotEmpty || moderators.isNotEmpty;
    return InkWell(
      onTap: () => context.push('/f/${item.fid}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item.icon.isEmpty
                  ? _placeholder(context, item.name)
                  : CachedNetworkImage(
                      imageUrl: item.icon,
                      httpHeaders: Api.imageHeaders,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      placeholder: (c, _) => _placeholder(c, item.name),
                      errorWidget: (c, _, _) => _placeholder(c, item.name),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    [
                      if (item.threads.isNotEmpty) '${item.threads} ${tr('主題')}',
                      if (item.posts.isNotEmpty) '${_short(item.posts)} ${tr('回覆')}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 11.5, color: faint(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 有子版塊／簡介／版主就變成展開鈕，沒有就維持指向內頁的箭頭
            if (!canExpand)
              Icon(LucideIcons.chevronRight, size: 18, color: faint(context))
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: expanded ? tr('收合') : tr('展開簡介與子版塊'),
                icon: Icon(
                    expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                    size: 20),
                onPressed: onToggle,
              ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext c, String name) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        color: Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.06),
        child: Text(name.isEmpty ? '?' : name.characters.first,
            style: TextStyle(fontWeight: FontWeight.w600, color: faint(c))),
      );
}

/// 展開後的版塊簡介與版主
class _ForumExpanded extends StatelessWidget {
  const _ForumExpanded({required this.item, this.moderators = const []});
  final ForumItem item;
  final List<String> moderators;

  @override
  Widget build(BuildContext context) {
    if (item.desc.isEmpty && moderators.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: .5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (moderators.isNotEmpty)
            Text('${tr('版主')}：${moderators.join('、')}',
                style: TextStyle(fontSize: 12, color: subtle(context))),
          if (item.desc.isNotEmpty) ...[
            if (moderators.isNotEmpty) const SizedBox(height: 6),
            Text(item.desc,
                style: TextStyle(
                    fontSize: 12.5, height: 1.6, color: subtle(context))),
          ],
        ],
      ),
    );
  }
}
