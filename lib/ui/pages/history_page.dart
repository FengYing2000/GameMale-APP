import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../i18n/ui.dart';
import '../../store/history.dart';
import '../../theme.dart';
import '../widgets/state_box.dart';

/// 回帖紀錄。存在本機，離線也翻得到
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<ReplyHistory>();
    final items = history.items;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('回帖紀錄')),
        actions: [
          if (items.isNotEmpty)
            IconButton(
              tooltip: tr('全部清除'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(tr('清除回帖紀錄？')),
                    content: Text(tr('只會清掉這份本機清單，論壇上的回覆不受影響。')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(tr('取消'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(tr('清除'))),
                    ],
                  ),
                );
                if (ok == true) await history.clear();
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? StateBox(
              empty: true,
              emptyText: tr('還沒有回帖紀錄。回覆主題之後會自動記在這裡。'),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (c, i) {
                final r = items[i];
                return Dismissible(
                  key: ValueKey(r.tid),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Theme.of(c).colorScheme.errorContainer,
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) => history.remove(r.tid),
                  child: ListTile(
                    onTap: () => context.push('/t/${r.tid}'),
                    title: Text(
                      r.title.isEmpty ? '#${r.tid}' : r.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, height: 1.4),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (r.excerpt.isNotEmpty)
                            Text(r.excerpt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: subtle(c))),
                          const SizedBox(height: 3),
                          Text(_when(r.at),
                              style:
                                  TextStyle(fontSize: 11.5, color: faint(c))),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

String _when(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return tr('剛剛');
  if (d.inHours < 1) return tr('${d.inMinutes} 分鐘前');
  if (d.inDays < 1) return tr('${d.inHours} 小時前');
  if (d.inDays < 7) return tr('${d.inDays} 天前');
  return '${t.year}-${t.month}-${t.day} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
