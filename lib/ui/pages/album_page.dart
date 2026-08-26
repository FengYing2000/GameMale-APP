import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/http.dart';
import '../../api/models.dart';
import '../../api/space.dart' as api;
import '../../i18n/ui.dart';
import '../widgets/image_viewer.dart';
import '../widgets/pager_bar.dart';
import '../widgets/state_box.dart';

/// 相冊內頁。縮圖排成格子，點開看原圖
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.uid, required this.albumId});
  final int uid;
  final int albumId;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  AlbumData? _data;
  bool _loading = true;
  String? _err;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int? page}) async {
    setState(() {
      _loading = true;
      _err = null;
      if (page != null) _page = page;
    });
    try {
      final d = await api.fetchAlbum(widget.uid, widget.albumId, page: _page);
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
      appBar: AppBar(
        title: Text(d?.title.isNotEmpty == true ? d!.title : tr('相冊')),
        bottom: d == null || d.count.isEmpty
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(22),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(d.count, style: const TextStyle(fontSize: 12)),
                ),
              ),
      ),
      bottomNavigationBar: d == null || d.photos.isEmpty
          ? null
          : StickyPager(pager: d.pager, onGo: (p) => _load(page: p)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(10),
          children: [
            ?StateBox.maybe(
              loading: _loading,
              error: _err,
              empty: !_loading && _err == null && (d?.photos.isEmpty ?? false),
              emptyText: d?.message ?? '',
              onRetry: _load,
            ),
            if (d != null && d.photos.isNotEmpty)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: d.photos.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemBuilder: (c, i) => InkWell(
                  onTap: () => showImageViewer(context, d.photos[i].full),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CachedNetworkImage(
                      imageUrl: d.photos[i].thumb,
                      httpHeaders: Api.imageHeaders,
                      fit: BoxFit.cover,
                      errorWidget: (c, _, _) =>
                          const Icon(LucideIcons.imageOff),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
