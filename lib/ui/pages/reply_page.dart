import '../../i18n/ui.dart';
import '../../store/replied.dart';
import '../../store/session.dart';
import '../widgets/composer_toolbar.dart';
import '../widgets/require_login.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
      // 網頁版是用彈窗顯示，這裡也顯示出來，才看得出到底有沒有加到分。
      // 帶 uid 是因為 cookie 最後一格記著它是給誰的，對不上就不能用
      final uid = context.read<SessionStore>().uid;
      final credits = await api.consumeCreditNotice(uid: uid);
      final rule = await api.consumeCreditRule();
      if (!mounted) return;

      // 剛回完就直接標起來，不用再去問論壇一次
      context.read<RepliedStore>().markReplied(widget.tid);
      toastCredits(
        context,
        message: r.message,
        rule: rule,
        credits: credits,
      );
      Navigator.of(context).pop(true);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('回覆失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr('回覆主題'))),
      body: Column(
        children: [
          // 回覆對象獨立一列，之前跟輸入框擠在標題上看不出來在回誰
          if (widget.to.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
              color: scheme.primary.withValues(alpha: .08),
              child: Row(
                children: [
                  Icon(LucideIcons.reply, size: 16, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${tr('回覆')} ${widget.to}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: 15.5, height: 1.6),
                decoration: InputDecoration(
                  hintText: tr('說點什麼…'),
                  filled: true,
                  fillColor: scheme.surface,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: scheme.primary, width: 1.4),
                  ),
                ),
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  ComposerToolbar(controller: _ctrl, focus: _focus),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr('支援 Discuz BBCode，[hide] 需要板塊開放權限'),
                            style: TextStyle(
                                fontSize: 11.5, color: faint(context)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(LucideIcons.send, size: 17),
                          label: Text(_busy ? tr('送出中') : tr('送出')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

