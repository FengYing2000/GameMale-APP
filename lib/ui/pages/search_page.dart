import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/http.dart';
import '../../api/models.dart';
import '../../api/search.dart' as api;
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.fid = 0, this.forumName = ''});

  /// 帶了就多一個「本版」分類，預設搜尋這個板塊
  final int fid;
  final String forumName;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  SearchScope _scope = SearchScope.forum;
  bool _thisForumOnly = false;
  SearchResult? _data;
  bool _loading = false;
  bool _done = false;
  String? _err;
  int _page = 1;

  // 高級搜索
  bool _advanced = false;
  bool _titleOnly = false;
  String _within = '';
  String _orderBy = '';

  @override
  void initState() {
    super.initState();
    _thisForumOnly = widget.fid > 0;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run(int page) async {
    final kw = _ctrl.text.trim();
    if (kw.characters.length < 2) return toast(context, tr('關鍵字至少 2 個字'));

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
        advanced: {
          if (_titleOnly) 'srchtype': 'title',
          if (_within.isNotEmpty) 'before': _within,
          if (_orderBy.isNotEmpty) 'orderby': _orderBy,
        },
      );
      if (!mounted) return;
      setState(() {
        _data = r;
        _done = true;
      });
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(SearchHit hit) {
    if (hit.tid != null) {
      context.push('/t/${hit.tid}');
      return;
    }
    if (hit.fid != null) {
      context.push('/f/${hit.fid}');
      return;
    }
    if (hit.uid != null && _scope == SearchScope.user) {
      context.push('/u/${hit.uid}');
      return;
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
          IconButton(
            icon: Icon(_advanced ? Icons.tune : Icons.tune_outlined),
            tooltip: tr('高級搜索'),
            onPressed: () => setState(() => _advanced = !_advanced),
          ),
        ],
      ),
      bottomNavigationBar: d == null || d.hits.isEmpty
          ? null
          : StickyPager(pager: d.pager, onGo: _run),
      body: ListView(
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
                  FilledButton(onPressed: () => _run(1), child: Text(tr('搜尋'))),
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
                      avatar: const Icon(Icons.folder_outlined, size: 15),
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

          if (_advanced) _advancedPanel(context),

          ?StateBox.maybe(
            loading: _loading,
            error: _err,
            empty: _done && !_loading && _err == null && (d?.hits.isEmpty ?? false),
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
                style: TextStyle(fontSize: 13, height: 1.6, color: faint(context)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _advancedPanel(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('高級搜索'),
                style: TextStyle(fontSize: 12.5, color: faint(context))),
            SwitchListTile(
              value: _titleOnly,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr('只搜尋標題'), style: const TextStyle(fontSize: 14)),
              onChanged: (v) => setState(() => _titleOnly = v),
            ),
            const SizedBox(height: 4),
            Text(tr('發表時間'), style: TextStyle(fontSize: 12, color: faint(context))),
            Wrap(
              spacing: 8,
              children: [
                for (final e in const [('', '不限'), ('1', '一天內'), ('7', '一週內'), ('30', '一個月內')])
                  ChoiceChip(
                    label: Text(tr(e.$2), style: const TextStyle(fontSize: 12.5)),
                    selected: _within == e.$1,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _within = e.$1),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(tr('排序'), style: TextStyle(fontSize: 12, color: faint(context))),
            Wrap(
              spacing: 8,
              children: [
                for (final e in const [('', '相關度'), ('dateline', '發表時間'), ('lastpost', '最後回覆'), ('views', '瀏覽數')])
                  ChoiceChip(
                    label: Text(tr(e.$2), style: const TextStyle(fontSize: 12.5)),
                    selected: _orderBy == e.$1,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _orderBy = e.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
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
                    errorWidget: (c, _, _) => const Icon(Icons.image_outlined),
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
