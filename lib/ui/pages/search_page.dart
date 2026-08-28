import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/http.dart';
import '../../api/discuz.dart' as discuz;
import '../../api/models.dart';
import '../../api/parse.dart';
import '../../api/search.dart' as api;
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class SearchPage extends StatefulWidget {
  const SearchPage(
      {super.key, this.fid = 0, this.forumName = '', this.initialQuery = ''});

  /// 帶了就多一個「本版」分類，預設搜尋這個板塊
  final int fid;
  final String forumName;

  /// 帶了就自動填入並搜尋（例如從專輯標籤點進來）
  final String initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _scroll = ScrollController();
  SearchScope _scope = SearchScope.forum;
  bool _thisForumOnly = false;
  SearchResult? _data;
  bool _loading = false;
  bool _done = false;
  String? _err;
  int _page = 1;

  bool _showAdvanced = false;
  AdvancedSearch _adv = const AdvancedSearch();

  /// 搜尋範圍要用的版塊清單，第一次打開高級搜索時才抓
  List<ForumGroup> _forumTree = const [];

  @override
  void initState() {
    super.initState();
    _thisForumOnly = widget.fid > 0;
    if (widget.initialQuery.isNotEmpty) {
      _ctrl.text = widget.initialQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(1);
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _authorCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run(int page) async {
    final kw = _ctrl.text.trim();
    // 論壇本身沒有 2 個字的限制，一個字也搜得到，所以只擋空白
    if (kw.isEmpty) return toast(context, tr('請先輸入關鍵字'));

    FocusScope.of(context).unfocus();
    setState(() {
      _page = page;
      _loading = true;
      _err = null;
    });
    try {
      final r = await api.search(
        kw,
        scope: _scope,
        page: page,
        fid: (_scope == SearchScope.forum && _thisForumOnly) ? widget.fid : 0,
        advanced: _scope == SearchScope.forum ? _adv : null,
      );
      if (!mounted) return;
      setState(() {
        _data = r;
        _done = true;
      });
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  Future<void> _loadForums() async {
    try {
      final idx = await discuz.fetchIndex();
      if (mounted) setState(() => _forumTree = idx.groups);
    } on DiscuzException {
      // 抓不到就不顯示範圍選擇，其他欄位照樣能用
    }
  }

  Future<void> _pickForums() async {
    final picked = {..._adv.forums};
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(c).size.height * .7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
                  child: Row(
                    children: [
                      Text(tr('搜尋範圍'),
                          style: TextStyle(fontSize: 12, color: faint(c))),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setSheet(picked.clear),
                        child: Text(tr('全部版塊')),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      for (final g in _forumTree) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                          child: Text(g.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: faint(c))),
                        ),
                        for (final f in g.forums)
                          CheckboxListTile(
                            dense: true,
                            value: picked.contains(f.fid),
                            title: Text(f.name,
                                style: const TextStyle(fontSize: 14)),
                            onChanged: (on) => setSheet(() {
                              if (on == true) {
                                picked.add(f.fid);
                              } else {
                                picked.remove(f.fid);
                              }
                            }),
                          ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(picked.isEmpty
                          ? tr('全部版塊')
                          : '${tr('已選')} ${picked.length}'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() => _adv = _adv.copyWith(forums: picked));
  }

  void _open(SearchHit hit) {
    // 淘帖搜尋結果的網址帶著 ctid
    final ctid = RegExp(r'ctid=(\d+)').firstMatch(hit.url);
    if (ctid != null) {
      context.push('/collection/${ctid.group(1)}');
      return;
    }
    if (hit.tid != null) {
      context.push('/t/${hit.tid}');
      return;
    }
    if (hit.fid != null) {
      context.push(
          _scope == SearchScope.group ? '/g/${hit.fid}' : '/f/${hit.fid}');
      return;
    }
    if (hit.uid != null && _scope == SearchScope.user) {
      context.push('/u/${hit.uid}');
      return;
    }
    // 日誌與相冊的搜尋結果，網址裡就帶著 uid 與內容 id
    final blog = RegExp(r'blog-(\d+)-(\d+)').firstMatch(hit.url);
    if (blog != null) {
      context.push('/blog/${blog.group(1)}/${blog.group(2)}');
      return;
    }
    if (hit.url.contains('do=album') && hit.uid != null) {
      final id = paramInt(hit.url, 'id');
      if (id != null) {
        context.push('/album/${hit.uid}/$id');
        return;
      }
    }
    if (hit.url.isNotEmpty) {
      launchUrl(Uri.parse(hit.url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('搜尋')),
        actions: [
          if (_scope == SearchScope.forum)
            IconButton(
              icon: Icon(_showAdvanced ? LucideIcons.slidersHorizontal : LucideIcons.slidersHorizontal),
              color:
                  _adv.isDefault ? null : Theme.of(context).colorScheme.primary,
              tooltip: tr('高級搜索'),
              onPressed: () {
                setState(() => _showAdvanced = !_showAdvanced);
                if (_showAdvanced && _forumTree.isEmpty) _loadForums();
              },
            ),
        ],
      ),
      bottomNavigationBar: d == null || d.hits.isEmpty
          ? null
          : StickyPager(pager: d.pager, onGo: _run),
      // 點空白處收鍵盤 —— 鍵盤擋著結果很難看
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          controller: _scroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _run(1),
                        decoration: InputDecoration(
                          hintText: tr('輸入關鍵字'),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: () => _run(1), child: Text(tr('搜尋'))),
                  ],
                ),
              ),
            ),

            // 分類
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                children: [
                  if (widget.fid > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: const Icon(LucideIcons.folder, size: 15),
                        label: Text(tr('本版')),
                        selected: _scope == SearchScope.forum && _thisForumOnly,
                        onSelected: (_) => setState(() {
                          _scope = SearchScope.forum;
                          _thisForumOnly = true;
                        }),
                      ),
                    ),
                  for (final s in SearchScope.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tr(s.label)),
                        selected: _scope == s &&
                            !(s == SearchScope.forum && _thisForumOnly),
                        onSelected: (_) => setState(() {
                          _scope = s;
                          _thisForumOnly = false;
                        }),
                      ),
                    ),
                ],
              ),
            ),

            if (_showAdvanced && _scope == SearchScope.forum)
              _advancedPanel(context),

            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty:
                  _done && !_loading && _err == null && (d?.hits.isEmpty ?? false),
              emptyText: d?.message ?? tr('找不到符合的內容'),
              onRetry: () => _run(_page),
            ),

            if (d != null && d.summary.isNotEmpty && d.hits.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: Text(d.summary,
                    style: TextStyle(fontSize: 12.5, color: faint(context))),
              ),

            if (d != null && d.hits.isNotEmpty)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < d.hits.length; i++) ...[
                      _HitTile(hit: d.hits[i], onTap: () => _open(d.hits[i])),
                      if (i != d.hits.length - 1)
                        const Divider(indent: 14, endIndent: 14),
                    ],
                  ],
                ),
              ),

            if (!_done && !_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 50, 30, 0),
                child: Text(
                  tr('論壇搜尋有頻率限制，短時間內連續搜尋會被暫時擋下。'),
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13, height: 1.6, color: faint(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 對應論壇的 search.php?mod=forum&adv=yes，欄位一個不少
  Widget _advancedPanel(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(tr('高級搜索'),
                    style: TextStyle(fontSize: 12.5, color: faint(context))),
                const Spacer(),
                if (!_adv.isDefault)
                  TextButton(
                    onPressed: () => setState(() {
                      _adv = const AdvancedSearch();
                      _authorCtrl.clear();
                    }),
                    child: Text(tr('重設')),
                  ),
              ],
            ),
            SwitchListTile(
              value: _adv.fulltext,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr('搜尋全文'), style: const TextStyle(fontSize: 14)),
              subtitle: Text(tr('預設只比對標題'),
                  style: TextStyle(fontSize: 11.5, color: faint(context))),
              onChanged: (v) =>
                  setState(() => _adv = _adv.copyWith(fulltext: v)),
            ),
            TextField(
              controller: _authorCtrl,
              decoration: InputDecoration(
                labelText: tr('作者'),
                hintText: tr('只搜這個人發的主題'),
                isDense: true,
              ),
              onChanged: (v) => _adv = _adv.copyWith(author: v.trim()),
            ),
            const SizedBox(height: 16),
            _label(tr('主題範圍')),
            _chips(
              options: [
                for (final o in searchScopeOptions)
                  (selected: _adv.scope == o.value, label: tr(o.label), onTap: () {
                    setState(() => _adv = _adv.copyWith(scope: o.value));
                  })
              ],
            ),
            const SizedBox(height: 12),
            _label(tr('特殊主題')),
            _chips(
              options: [
                for (final o in searchSpecialOptions)
                  (
                    selected: _adv.special.contains(o.value),
                    label: tr(o.label),
                    onTap: () => setState(() {
                      final next = {..._adv.special};
                      if (next.contains(o.value)) {
                        next.remove(o.value);
                      } else {
                        next.add(o.value);
                      }
                      _adv = _adv.copyWith(special: next);
                    }),
                  )
              ],
            ),
            const SizedBox(height: 12),
            _label(tr('搜尋時間')),
            _chips(
              options: [
                for (final o in searchTimeOptions)
                  (
                    selected: _adv.srchfrom == o.value,
                    label: tr(o.label),
                    onTap: () =>
                        setState(() => _adv = _adv.copyWith(srchfrom: o.value)),
                  )
              ],
            ),
            if (_adv.srchfrom > 0) ...[
              const SizedBox(height: 8),
              _chips(
                options: [
                  (
                    selected: !_adv.before,
                    label: tr('以內'),
                    onTap: () =>
                        setState(() => _adv = _adv.copyWith(before: false)),
                  ),
                  (
                    selected: _adv.before,
                    label: tr('以前'),
                    onTap: () =>
                        setState(() => _adv = _adv.copyWith(before: true)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _label(tr('搜尋範圍')),
            OutlinedButton.icon(
              onPressed: _forumTree.isEmpty ? null : _pickForums,
              icon: const Icon(LucideIcons.listChecks, size: 17),
              label: Text(
                _adv.forums.isEmpty
                    ? tr('全部版塊')
                    : '${tr('已選')} ${_adv.forums.length} ${tr('個版塊')}',
              ),
            ),
            const SizedBox(height: 12),
            _label(tr('排序')),
            _chips(
              options: [
                for (final o in searchOrderOptions)
                  (
                    selected: _adv.orderby == o.value,
                    label: tr(o.label),
                    onTap: () =>
                        setState(() => _adv = _adv.copyWith(orderby: o.value)),
                  ),
                (
                  selected: _adv.ascending,
                  label: tr('由舊到新'),
                  onTap: () => setState(
                      () => _adv = _adv.copyWith(ascending: !_adv.ascending)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child:
            Text(text, style: TextStyle(fontSize: 12, color: faint(context))),
      );

  Widget _chips({
    required List<({bool selected, String label, VoidCallback onTap})> options,
  }) =>
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final o in options)
            ChoiceChip(
              label: Text(o.label, style: const TextStyle(fontSize: 12.5)),
              selected: o.selected,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => o.onTap(),
            ),
        ],
      );
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.onTap});
  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasCover = hit.image.isNotEmpty && hit.uid == null;
    return ListTile(
      onTap: onTap,
      leading: hit.image.isEmpty
          ? null
          : (hasCover
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: hit.image,
                    httpHeaders: Api.imageHeaders,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorWidget: (c, _, _) => const Icon(LucideIcons.image),
                  ),
                )
              : Avatar(hit.image, size: 40)),
      title: Text(hit.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14.5, height: 1.4)),
      subtitle: hit.subtitle.isEmpty
          ? null
          : Text(hit.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: faint(context))),
    );
  }
}
