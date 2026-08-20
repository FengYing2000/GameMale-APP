import 'package:flutter/material.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../theme.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';
import '../widgets/thread_tile.dart';
import '../widgets/toast.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  ListPage? _data;
  bool _loading = false;
  bool _done = false;
  String? _err;
  int _page = 1;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _run(int page) async {
    final kw = _ctrl.text.trim();
    if (kw.characters.length < 2) return toast(context, '關鍵字至少 2 個字');

    setState(() {
      _page = page;
      _loading = true;
      _err = null;
    });
    try {
      final d = await api.search(kw, page: page);
      if (!mounted) return;
      setState(() {
        _data = d;
        _done = true;
      });
      if (d.list.isEmpty && d.message != null) toast(context, d.message!);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(title: const Text('搜尋')),
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
                      decoration: const InputDecoration(
                        hintText: '搜尋主題關鍵字',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => _run(1), child: const Text('搜尋')),
                ],
              ),
            ),
          ),
          ?StateBox.maybe(
            loading: _loading,
            error: _err,
            empty: _done && !_loading && _err == null && (d?.list.isEmpty ?? false),
            emptyText: '找不到符合的主題',
            onRetry: () => _run(_page),
          ),
          if (d != null && d.list.isNotEmpty) ...[
            ThreadListCard(list: d.list),
            PagerBar(pager: d.pager, onGo: _run),
          ],
          if (!_done && !_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 60, 30, 0),
              child: Text(
                '論壇搜尋有頻率限制，短時間內連續搜尋會被暫時擋下。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.6, color: faint(context)),
              ),
            ),
        ],
      ),
    );
  }
}
