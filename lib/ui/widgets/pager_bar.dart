import '../../i18n/ui.dart';
import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme.dart';

/// 固定在底部的分頁列，不必捲到最後才看得到。
/// 點頁碼可以直接跳頁。
class StickyPager extends StatelessWidget {
  const StickyPager({super.key, required this.pager, required this.onGo});

  final PageInfo pager;
  final ValueChanged<int> onGo;

  Future<void> _pick(BuildContext context) async {
    final target = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheet).size.height * 0.6),
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 72,
              childAspectRatio: 1.7,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: pager.total,
            itemBuilder: (c, i) {
              final n = i + 1;
              return OutlinedButton(
                onPressed: () => Navigator.pop(sheet, n),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: n == pager.page
                      ? Theme.of(c).colorScheme.primary.withValues(alpha: 0.15)
                      : null,
                ),
                child: Text('$n'),
              );
            },
          ),
        ),
      ),
    );
    if (target != null && target != pager.page) onGo(target);
  }

  @override
  Widget build(BuildContext context) {
    if (pager.total <= 1) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: pager.page > 1 ? () => onGo(pager.page - 1) : null,
              icon: const Icon(Icons.chevron_left),
              tooltip: tr('上一頁'),
            ),
            TextButton(
              onPressed: () => _pick(context),
              child: Text('${pager.page} / ${pager.total}',
                  style: const TextStyle(fontSize: 14)),
            ),
            IconButton(
              onPressed: pager.page < pager.total ? () => onGo(pager.page + 1) : null,
              icon: const Icon(Icons.chevron_right),
              tooltip: tr('下一頁'),
            ),
          ],
        ),
      ),
    );
  }
}

class PagerBar extends StatelessWidget {
  const PagerBar({super.key, required this.pager, required this.onGo});

  final PageInfo pager;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    if (pager.total <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton(
            onPressed: pager.page > 1 ? () => onGo(pager.page - 1) : null,
            child: Text(tr('上一頁')),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${pager.page} / ${pager.total}',
                style: TextStyle(color: subtle(context), fontSize: 13)),
          ),
          OutlinedButton(
            onPressed: pager.page < pager.total ? () => onGo(pager.page + 1) : null,
            child: Text(tr('下一頁')),
          ),
        ],
      ),
    );
  }
}
