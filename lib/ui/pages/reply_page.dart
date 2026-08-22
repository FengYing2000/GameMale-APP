import '../../i18n/ui.dart';
import '../../store/history.dart';
import '../widgets/composer_toolbar.dart';
import '../widgets/require_login.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    this.threadTitle = '',
  });

  final int tid;
  final int fid;
  final int page;
  final String repquote;
  final String to;

  /// 只用來寫進本機的回帖紀錄
  final String threadTitle;

  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends State<ReplyPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

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

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return toast(context, tr('內容不能空白'));
    if (!await requireLogin(context, action: tr('回覆主題'))) return;
    if (!mounted) return;

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
      if (!r.ok) {
        toast(context, r.message);
        return;
      }

      // 發文成功後論壇會把積分變化寫進 cookie（勳章觸發也走這套），
      // 網頁版是用彈窗顯示，這裡也顯示出來，才看得出到底有沒有加到分
      final credits = await api.consumeCreditNotice();
      if (!mounted) return;

      await context.read<ReplyHistory>().add(ReplyRecord(
            tid: widget.tid,
            title: widget.threadTitle,
            excerpt: text.length > 80 ? '${text.substring(0, 80)}…' : text,
            at: DateTime.now(),
          ));
      if (!mounted) return;
      toast(context,
          credits.isEmpty ? r.message : '${r.message}　${credits.join('　')}');
      Navigator.of(context).pop(true);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('回覆失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.to.isEmpty ? tr('回覆主題') : tr('回覆 ${widget.to}')),
        actions: [
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? tr('送出中') : tr('送出')),
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
                  decoration: InputDecoration(
                    hintText: tr('說點什麼…'),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
          ),
          ComposerToolbar(controller: _ctrl, focus: _focus),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                tr('支援 Discuz BBCode。[hide] 需要板塊開放回覆可見權限才有效。'),
                style: TextStyle(fontSize: 12, color: faint(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
