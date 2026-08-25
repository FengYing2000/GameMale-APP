import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/ui.dart';
import '../../store/settings.dart';
import '../../theme.dart';
import '../widgets/quick_menu.dart' show forumTools;

/// 編排側邊欄的「論壇功能」：拖曳排序、開關顯示
class ToolsPage extends StatefulWidget {
  const ToolsPage({super.key});

  @override
  State<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends State<ToolsPage> {
  late List<String> _order;
  late Set<String> _on;

  @override
  void initState() {
    super.initState();
    final s = context.read<SettingsStore>();
    _on = {for (final t in s.visibleTools) t.id};
    // 關掉的排在後面，這樣拖曳時看得到全部
    _order = [
      for (final t in s.visibleTools) t.id,
      for (final t in s.hiddenTools) t.id,
    ];
    // 從沒設定過的話 hiddenTools 是空的，補齊漏掉的
    for (final t in forumTools) {
      if (!_order.contains(t.id)) _order.add(t.id);
    }
  }

  void _save() {
    context
        .read<SettingsStore>()
        .setToolOrder([for (final id in _order) if (_on.contains(id)) id]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('論壇功能')),
        actions: [
          TextButton(
            onPressed: () {
              context.read<SettingsStore>().resetTools();
              setState(() {
                _order = [for (final t in forumTools) t.id];
                _on = {for (final t in forumTools) t.id};
              });
            },
            child: Text(tr('還原預設')),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Text(
              tr('長按右邊的把手可以拖曳排序，開關決定要不要出現在側邊欄。'),
              style: TextStyle(fontSize: 12.5, height: 1.6, color: faint(context)),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: _order.length,
              // onReorderItem 已經幫忙修正過索引，不用自己 -1
              onReorderItem: (from, to) {
                setState(() => _order.insert(to, _order.removeAt(from)));
                _save();
              },
              itemBuilder: (c, i) {
                final id = _order[i];
                final tool = forumTools.where((t) => t.id == id).firstOrNull;
                if (tool == null) return SizedBox.shrink(key: ValueKey(id));
                return SwitchListTile(
                  key: ValueKey(id),
                  value: _on.contains(id),
                  secondary: SizedBox(
                    width: 26,
                    child: Text(tool.icon,
                        style: const TextStyle(fontSize: 17),
                        textAlign: TextAlign.center),
                  ),
                  title: Text(tr(tool.label),
                      style: const TextStyle(fontSize: 14.5)),
                  onChanged: (v) {
                    setState(() => v ? _on.add(id) : _on.remove(id));
                    _save();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
