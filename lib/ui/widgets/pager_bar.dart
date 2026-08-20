import '../../i18n/ui.dart';
import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../theme.dart';

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
