import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:gm_api/models.dart';
import '../../store/replied.dart';
import '../../theme.dart';
import 'avatar.dart';

String compact(int n) => n >= 10000 ? '${(n / 10000).toStringAsFixed(1)}萬' : '$n';

class ThreadTile extends StatelessWidget {
  const ThreadTile({super.key, required this.item, this.onRemove});

  final ThreadItem item;

  /// 收藏列表才傳，顯示「取消收藏」
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final meta = TextStyle(fontSize: 12, color: faint(context));
    final repliedStore = context.watch<RepliedStore>();
    final replied = repliedStore.statusOf(item.tid);
    // 由每一列自己排隊查，這樣首頁、搜尋、收藏各種列表都會標，
    // 設定一打開也會因為重繪而自動補查
    if (replied == null) repliedStore.check([item.tid]);
    // 手機版列表不標閱讀權限；「已回」那次查詢撞到權限不足時才知道。
    // 那種一定是自己看不到的，加上鎖頭
    final denied = repliedStore.deniedReadPerm(item.tid);
    final readPerm = item.readPerm > 0 ? item.readPerm : denied;

    return InkWell(
      onTap: () => context.push('/t/${item.tid}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(children: [
                // 已回帖標記放在最前面，一眼掃得到
                if (replied == true)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32).withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(tr('已回'),
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32))),
                    ),
                  ),
                if (item.type.isNotEmpty)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: brand.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(item.type,
                          style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary)),
                    ),
                  ),
                // 關閉的主題：網頁版是鎖頭圖示，點進去也回不了帖
                if (item.closed)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: Tooltip(
                        message: tr('已關閉的主題，無法回帖'),
                        child: Icon(LucideIcons.lock,
                            size: 14, color: faint(context)),
                      ),
                    ),
                  ),
                if (readPerm > 0)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: _ReadPermBadge(readPerm: readPerm, denied: denied > 0),
                  ),
                TextSpan(text: item.title),
              ]),
              style: const TextStyle(fontSize: 15, height: 1.42, fontWeight: FontWeight.w600),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.digest.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                item.digest,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 1.5, color: subtle(context)),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (item.avatar.isNotEmpty) ...[
                  Avatar(item.avatar,
                      size: 22,
                      onTap: item.uid == null ? null : () => context.push('/u/${item.uid}')),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Text(
                    [
                      if (item.author.isNotEmpty) item.author,
                      if (item.date.isNotEmpty) item.date,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: meta,
                  ),
                ),
                if (onRemove != null)
                  TextButton(
                    onPressed: onRemove,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 28),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(tr('取消收藏'), style: TextStyle(fontSize: 12, color: subtle(context))),
                  ),
                if (item.replies > 0) ...[
                  Icon(LucideIcons.messageSquare, size: 13, color: faint(context)),
                  const SizedBox(width: 3),
                  Text(compact(item.replies), style: meta),
                  const SizedBox(width: 10),
                ],
                if (item.views > 0) ...[
                  Icon(LucideIcons.eye, size: 14, color: faint(context)),
                  const SizedBox(width: 3),
                  Text(compact(item.views), style: meta),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 「閱讀權限 105」。[denied]＝已確認自己看不到，前面多一個鎖頭
class _ReadPermBadge extends StatelessWidget {
  const _ReadPermBadge({required this.readPerm, required this.denied});
  final int readPerm;
  final bool denied;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFF0B14A)
        : const Color(0xFFA35F00);
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFFE08E0B).withValues(alpha: .16),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (denied) ...[
            Icon(LucideIcons.lock, size: 10.5, color: color),
            const SizedBox(width: 3),
          ],
          Text('${tr('閱讀權限')} $readPerm',
              style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

/// 一整張卡片包住一串主題，分隔線交給 Divider
class ThreadListCard extends StatelessWidget {
  const ThreadListCard({super.key, required this.list, this.onRemove});

  final List<ThreadItem> list;
  final void Function(ThreadItem)? onRemove;

  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < list.length; i++) ...[
            ThreadTile(
              item: list[i],
              onRemove: onRemove == null ? null : () => onRemove!(list[i]),
            ),
            if (i != list.length - 1) const Divider(indent: 14, endIndent: 14),
          ],
        ],
      ),
    );
  }
}
