import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../api/space.dart' as api;
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/post_body.dart';
import '../widgets/state_box.dart';

/// 日誌內頁
class BlogPage extends StatefulWidget {
  const BlogPage({super.key, required this.uid, required this.blogId});
  final int uid;
  final int blogId;

  @override
  State<BlogPage> createState() => _BlogPageState();
}

class _BlogPageState extends State<BlogPage> {
  BlogData? _data;
  bool _loading = true;
  String? _err;

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
      final d = await api.fetchBlog(widget.uid, widget.blogId);
      if (mounted) setState(() => _data = d);
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
      appBar: AppBar(title: Text(tr('日誌'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && (d?.html.isEmpty ?? false),
              emptyText: d?.message ?? '',
              onRetry: _load,
            ),
            if (d != null && d.html.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(d.title,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
              ),
              if (d.meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Text(d.meta,
                      style: TextStyle(fontSize: 12, color: faint(context))),
                ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: PostBody(d.html),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
