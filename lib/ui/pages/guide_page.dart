import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../store/session.dart';
import '../../api/models.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/thread_tile.dart';

class GuidePage extends StatefulWidget {
  const GuidePage({super.key});

  @override
  State<GuidePage> createState() => _GuidePageState();
}

class _GuidePageState extends State<GuidePage> {
  static const _views = [
    ('newthread', '最新發表'),
    ('hot', '熱門'),
    ('digest', '精華'),
    ('new', '最新回覆'),
  ];

  String _view = 'newthread';
  int _page = 1;
  ListPage? _data;
  bool _loading = true;
  String? _err;
  final _scroll = ScrollController();


  int _rev = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 登入/登出後這個分頁還被保活著，靠 revision 判斷要不要重抓。
    // 第一次只記錄不重抓 —— initState 已經載過了，否則每次開頁都會抓兩遍
    final rev = context.watch<SessionStore>().revision;
    if (_rev == -1) {
      _rev = rev;
      return;
    }
    if (_rev != rev) {
      _rev = rev;
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

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.fetchGuide(view: _view, page: _page);
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(title: Text(tr('導讀'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
                children: [
                  for (final v in _views)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(tr(v.$2)),
                        selected: _view == v.$1,
                        onSelected: (_) {
                          setState(() {
                            _view = v.$1;
                            _page = 1;
                          });
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && (d?.list.isEmpty ?? false),
              onRetry: _load,
            ),
            if (d != null && d.list.isNotEmpty) ThreadListCard(list: d.list),
            if (d != null)
              PagerBar(
                pager: d.pager,
                onGo: (p) {
                  setState(() => _page = p);
                  _load();
                },
              ),
          ],
        ),
      ),
    );
  }
}
