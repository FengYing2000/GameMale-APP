import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/http.dart';
import '../../api/models.dart';
import '../../api/smilies.dart' as api;
import '../../i18n/ui.dart';
import '../../theme.dart';

/// 發文／回覆／編輯共用的工具列：BBCode 快捷鍵 + 表情選擇器
class ComposerToolbar extends StatelessWidget {
  const ComposerToolbar({
    super.key,
    required this.controller,
    required this.focus,
  });

  final TextEditingController controller;
  final FocusNode focus;

  static const _tools = [
    ('B', '[b]', '[/b]'),
    ('I', '[i]', '[/i]'),
    ('U', '[u]', '[/u]'),
    ('引用', '[quote]', '[/quote]'),
    ('圖片', '[img]', '[/img]'),
    ('連結', '[url=]', '[/url]'),
    ('隱藏', '[hide]', '[/hide]'),
  ];

  /// 包 BBCode，並把選取範圍留在標籤中間
  void wrap(String open, String close) {
    final sel = controller.selection;
    final text = controller.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final inner = text.substring(start, end);

    controller.value = TextEditingValue(
      text: text.replaceRange(start, end, '$open$inner$close'),
      selection: TextSelection(
        baseOffset: start + open.length,
        extentOffset: start + open.length + inner.length,
      ),
    );
    focus.requestFocus();
  }

  void _insert(String code) {
    final sel = controller.selection;
    final text = controller.text;
    final at = sel.end < 0 ? text.length : sel.end;
    controller.value = TextEditingValue(
      text: text.replaceRange(sel.start < 0 ? at : sel.start, at, code),
      selection: TextSelection.collapsed(
          offset: (sel.start < 0 ? at : sel.start) + code.length),
    );
  }

  Future<void> _pickSmiley(BuildContext context) async {
    // 鍵盤收起來，不然表情面板只剩一條縫
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SmileySheet(onPick: _insert),
    );
    focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 5, bottom: 5),
            child: ActionChip(
              avatar: const Icon(LucideIcons.smile, size: 17),
              label: Text(tr('表情')),
              onPressed: () => _pickSmiley(context),
            ),
          ),
          for (final t in _tools)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 5, bottom: 5),
              child: ActionChip(
                label: Text(tr(t.$1)),
                onPressed: () => wrap(t.$2, t.$3),
              ),
            ),
        ],
      ),
    );
  }
}

class _SmileySheet extends StatefulWidget {
  const _SmileySheet({required this.onPick});
  final void Function(String code) onPick;

  @override
  State<_SmileySheet> createState() => _SmileySheetState();
}

class _SmileySheetState extends State<_SmileySheet> {
  List<api.SmileyGroup>? _groups;
  String? _err;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _err = null);
    try {
      final g = await api.fetchSmilies();
      if (mounted) setState(() => _groups = g);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _groups;
    final height = MediaQuery.of(context).size.height * .45;

    return SizedBox(
      height: height,
      child: g == null
          ? Center(
              child: _err == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_err!,
                            style:
                                TextStyle(fontSize: 13, color: faint(context))),
                        const SizedBox(height: 10),
                        TextButton(onPressed: _load, child: Text(tr('重試'))),
                      ],
                    ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (var i = 0; i < g.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(g[i].name,
                                style: const TextStyle(fontSize: 12.5)),
                            selected: _tab == i,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) => setState(() => _tab = i),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: g[_tab].items.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      crossAxisSpacing: 6,
                      mainAxisSpacing: 6,
                    ),
                    itemBuilder: (c, i) {
                      final s = g[_tab].items[i];
                      return InkWell(
                        onTap: () {
                          widget.onPick(s.code);
                          Navigator.pop(c);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: CachedNetworkImage(
                            imageUrl: s.url,
                            httpHeaders: Api.imageHeaders,
                            fit: BoxFit.contain,
                            errorWidget: (c, _, _) =>
                                const Icon(LucideIcons.imageOff, size: 16),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
