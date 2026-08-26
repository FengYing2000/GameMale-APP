import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/http.dart';

class Avatar extends StatelessWidget {
  const Avatar(this.url, {super.key, this.size = 38, this.onTap});

  final String url;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ph = Container(
      width: size,
      height: size,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
      child: Icon(LucideIcons.user, size: size * 0.6, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
    );

    // AppBar 的 leading 會給「寬 56、高滿版」的緊約束，SizedBox 擋不住，
    // ClipOval 就依那個框裁成直橢圓。
    // Align 帶 widthFactor/heightFactor 會縮到子元件尺寸並改給鬆約束，
    // 兩個問題一次解決 —— 不能用 Center，它會撐滿寬度把旁邊文字擠爆。
    return GestureDetector(
      onTap: onTap,
      child: Align(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox(
          width: size,
          height: size,
          child: ClipOval(
            child: url.isEmpty
                ? ph
                : CachedNetworkImage(
                    imageUrl: url,
                    httpHeaders: Api.imageHeaders,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    placeholder: (c, _) => ph,
                    errorWidget: (c, _, _) => ph,
                  ),
          ),
        ),
      ),
    );
  }
}
