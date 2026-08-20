import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/http.dart';
import '../../api/parse.dart';
import '../../theme.dart';
import 'image_viewer.dart';

/// 渲染 Discuz 的帖子 HTML。
///
/// 論壇內容是手工拼出來的任意 HTML（巢狀 font、表格、spoiler、表情圖），
/// 這裡把三件事接管掉：站內連結導航、圖片點擊放大、spoiler 折疊。
class PostBody extends StatelessWidget {
  const PostBody(this.html, {super.key, this.textStyle});

  final String html;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) return const SizedBox.shrink();

    return HtmlWidget(
      html,
      textStyle: textStyle ?? const TextStyle(fontSize: 15.5, height: 1.7),
      onTapUrl: (url) => _openUrl(context, url),
      customWidgetBuilder: (element) {
        // spoiler：sanitize 時標成 data-spoiler，這裡畫成可展開區塊
        final label = element.attributes['data-spoiler'];
        if (label != null) {
          return _Spoiler(label: label, inner: element.innerHtml);
        }

        // 內容圖：走快取 + 點擊全螢幕；表情圖維持行內不攔截
        if (element.localName == 'img' && element.classes.contains('post-img')) {
          final src = element.attributes['src'];
          if (src != null && src.isNotEmpty) return _PostImage(src: src);
        }
        return null;
      },
      customStylesBuilder: (element) {
        if (element.classes.contains('smiley')) {
          return {'width': '22px', 'height': '22px'};
        }
        // 論壇很愛用 <font size=5> 之類的，交給 App 自己的排版比較一致
        if (element.localName == 'font' && element.attributes.containsKey('size')) {
          return {'font-size': '1em'};
        }
        return null;
      },
    );
  }

  /// 站內連結留在 App 裡，站外交給系統瀏覽器
  bool _openUrl(BuildContext context, String url) {
    if (!url.startsWith(kOrigin)) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return true;
    }

    // redirect 連結（通知、樓中樓）的主題 id 放在 ptid
    final tid = paramInt(url, 'tid') ??
        paramInt(url, 'ptid') ??
        int.tryParse(RegExp(r'thread-(\d+)').firstMatch(url)?.group(1) ?? '');
    final fid = paramInt(url, 'fid') ??
        int.tryParse(RegExp(r'forum-(\d+)').firstMatch(url)?.group(1) ?? '');
    final uid = paramInt(url, 'uid') ??
        int.tryParse(RegExp(r'space-uid-(\d+)').firstMatch(url)?.group(1) ?? '');

    if (tid != null) {
      context.push('/t/$tid');
    } else if (fid != null) {
      context.push('/f/$fid');
    } else if (uid != null) {
      context.push('/u/$uid');
    } else {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
    return true;
  }
}

class _Spoiler extends StatelessWidget {
  const _Spoiler({required this.label, required this.inner});
  final String label;
  final String inner;

  @override
  Widget build(BuildContext context) {
    // ExpansionTile 內含 ListTile，背景色必須由 Material 提供，
    // 包在 DecoratedBox 裡會讓水波紋和背景失效（Flutter 會直接報錯）。
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            title: Text(
              label,
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary),
            ),
            children: [PostBody(inner)],
          ),
        ),
      ),
    );
  }
}

class _PostImage extends StatelessWidget {
  const _PostImage({required this.src});
  final String src;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () => showImageViewer(context, src),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: src,
            httpHeaders: Api.imageHeaders,
            fit: BoxFit.contain,
            placeholder: (c, _) => Container(
              height: 150,
              alignment: Alignment.center,
              color: Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.04),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (c, _, _) => Container(
              height: 90,
              alignment: Alignment.center,
              color: Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.04),
              child: Text('圖片載入失敗', style: TextStyle(fontSize: 12, color: faint(c))),
            ),
          ),
        ),
      ),
    );
  }
}
