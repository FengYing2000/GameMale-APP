import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/http.dart';
import '../../api/parse.dart';
import '../../store/settings.dart';
import '../../theme.dart';
import 'image_actions.dart';
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

        final styles = <String, String>{};

        // <font size=5> 之類的交給 App 自己的排版，比較一致
        if (element.localName == 'font' && element.attributes.containsKey('size')) {
          styles['font-size'] = '1em';
        }

        // 深／淺色底都要讀得到帖子裡指定的文字顏色
        final isDark = Theme.of(context).brightness == Brightness.dark;
        var raw = element.attributes['color'];
        if (raw == null) {
          final inline = element.attributes['style'];
          if (inline != null) {
            raw = RegExp(r'(?:^|;)\s*color\s*:\s*([^;]+)')
                .firstMatch(inline)
                ?.group(1);
          }
        }
        final fixed = _readable(raw, isDark);
        if (fixed != null) styles['color'] = fixed;

        return styles.isEmpty ? null : styles;
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


/// 論壇很愛用 `<font color="#8b0000">` 這種深色標重點，配深色底幾乎看不見。
/// 直接拿掉顏色會失去語意，所以保留色相、只把亮度拉進可讀區間。
String? _readable(String? raw, bool isDark) {
  if (raw == null) return null;
  final c = _parseColor(raw.trim());
  if (c == null) return null;

  final hsl = HSLColor.fromColor(c);
  // 深色底要夠亮、淺色底要夠暗，門檻留一點餘裕避免過度校正
  final l = isDark ? (hsl.lightness < 0.55 ? 0.68 : hsl.lightness)
                   : (hsl.lightness > 0.72 ? 0.42 : hsl.lightness);
  if (l == hsl.lightness) return null;   // 本來就夠讀就不要動

  // 灰階（低飽和）直接交還給主題預設色，硬拉亮度只會變成髒灰
  if (hsl.saturation < 0.12) return null;

  final out = hsl.withLightness(l).toColor();
  return '#${(out.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

const _named = {
  'red': 0xFFFF0000, 'darkred': 0xFF8B0000, 'blue': 0xFF0000FF,
  'darkblue': 0xFF00008B, 'green': 0xFF008000, 'darkgreen': 0xFF006400,
  'purple': 0xFF800080, 'orange': 0xFFFFA500, 'brown': 0xFFA52A2A,
  'sienna': 0xFFA0522D, 'teal': 0xFF008080, 'navy': 0xFF000080,
  'maroon': 0xFF800000, 'olive': 0xFF808000, 'gray': 0xFF808080,
  'grey': 0xFF808080, 'black': 0xFF000000, 'white': 0xFFFFFFFF,
  'dimgray': 0xFF696969, 'darkslategray': 0xFF2F4F4F,
};

Color? _parseColor(String raw) {
  var v = raw.toLowerCase();
  if (_named.containsKey(v)) return Color(_named[v]!);

  final rgb = RegExp(r'rgba?\(\s*(\d+)\D+(\d+)\D+(\d+)').firstMatch(v);
  if (rgb != null) {
    return Color.fromARGB(255, int.parse(rgb.group(1)!),
        int.parse(rgb.group(2)!), int.parse(rgb.group(3)!));
  }

  if (!v.startsWith('#')) return null;
  v = v.substring(1);
  if (v.length == 3) v = v.split('').map((ch) => '$ch$ch').join();
  if (v.length != 6) return null;
  final n = int.tryParse(v, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
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

class _PostImage extends StatefulWidget {
  const _PostImage({required this.src});
  final String src;

  @override
  State<_PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<_PostImage> {
  /// 手動載入模式下，使用者點過就記住，換頁前不再問
  bool _forced = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsStore>();
    final show = _forced || settings.autoLoadImages;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: show ? _image(context) : _placeholder(context, settings),
    );
  }

  Widget _placeholder(BuildContext context, SettingsStore settings) {
    final reason = settings.imagePolicy == ImagePolicy.wifiOnly
        ? '目前不是 Wi-Fi'
        : '已設為手動載入';
    return InkWell(
      onTap: () => setState(() => _forced = true),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 96,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 24, color: faint(context)),
            const SizedBox(height: 6),
            Text('點一下載入圖片',
                style: TextStyle(fontSize: 13, color: subtle(context))),
            Text(reason, style: TextStyle(fontSize: 11, color: faint(context))),
          ],
        ),
      ),
    );
  }

  Widget _image(BuildContext context) {
    return GestureDetector(
      onTap: () => showImageViewer(context, widget.src),
      onLongPress: () => showImageActions(context, widget.src),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: widget.src,
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
    );
  }
}
