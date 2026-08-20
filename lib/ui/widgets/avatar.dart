import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

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
      child: Icon(Icons.person, size: size * 0.6, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25)),
    );

    return GestureDetector(
      onTap: onTap,
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
    );
  }
}
