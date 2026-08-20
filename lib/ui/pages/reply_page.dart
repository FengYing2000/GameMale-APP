import 'package:flutter/material.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../theme.dart';
import '../widgets/toast.dart';

class ReplyPage extends StatefulWidget {
  const ReplyPage({
    super.key,
    required this.tid,
    required this.fid,
    this.page = 1,
    this.repquote = '',
    this.to = '',
  });

  final int tid;
  final int fid;
  final int page;
  final String repquote;
  final String to;

  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends State<ReplyPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  static const _tools = [
    ('B', '[b]', '[/b]'),
    ('I', '[i]', '[/i]'),
    ('U', '[u]', '[/u]'),
    ('引用', '[quote]', '[/quote]'),
    ('圖片', '[img]', '[/img]'),
    ('連結', '[url=]', '[/url]'),
    ('隱藏', '[hide]', '[/hide]'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 包 BBCode，並把選取範圍留在標籤中間
  void _wrap(String open, String close) {
    final sel = _ctrl.selection;
    final text = _ctrl.text;
    final start = sel.start < 0 ? text.length : sel.start;
    final end = sel.end < 0 ? text.length : sel.end;
    final inner = text.substring(start, end);

    _ctrl.value = TextEditingValue(
      text: text.replaceRange(start, end, '$open$inner$close'),
      selection: TextSelection(
        baseOffset: start + open.length,
        extentOffset: start + open.length + inner.length,
      ),
    );
    _focus.requestFocus();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return toast(context, '內容不能空白');

    setState(() => _busy = true);
    try {
      final r = await api.replyThread(
        fid: widget.fid,
        tid: widget.tid,
        message: text,
        repquote: widget.repquote,
        page: widget.page,
      );
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) Navigator.of(context).pop(true);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '回覆失敗：${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.to.isEmpty ? '回覆主題' : '回覆 ${widget.to}'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '送出中' : '送出'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '說點什麼…',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final t in _tools)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 5, bottom: 5),
                    child: ActionChip(
                      label: Text(t.$1),
                      onPressed: () => _wrap(t.$2, t.$3),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '支援 Discuz BBCode。[hide] 需要板塊開放回覆可見權限才有效。',
                style: TextStyle(fontSize: 12, color: faint(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
