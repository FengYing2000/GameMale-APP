import '../../i18n/ui.dart';
import '../../store/replied.dart';
import '../../store/session.dart';
import '../widgets/composer_toolbar.dart';
import '../widgets/require_login.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/models.dart';
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

  /// 能不能回、字數限制。問不到就是 null，照舊讓使用者送、由論壇決定
  ReplyGate? _gate;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
    _loadGate();
  }

  Future<void> _loadGate() async {
    if (!context.read<SessionStore>().loggedIn) return;
    try {
      final g = await api.replyGate(fid: widget.fid, tid: widget.tid);
      if (mounted) setState(() => _gate = g);
    } on DiscuzException {
      // 問不到不影響回帖
    }
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
    final g = _gate;
    if (g != null && !g.allowed) {
      return toast(context, sys(g.message), kind: ToastKind.warn);
    }
    // 跟網頁版一樣先擋字數，別讓使用者等一趟才被論壇退回
    final bytes = api.postBytes(text);
    if (g != null && g.minBytes > 0 && bytes < g.minBytes) {
      return toast(
          context,
          tr('內容太短：論壇要求至少 ${g.minBytes} 位元組'
              '（中文一字算 3、英數算 1），目前 $bytes'),
          kind: ToastKind.warn);
    }
    if (g != null && g.maxBytes > 0 && bytes > g.maxBytes) {
      return toast(
          context, tr('內容太長：論壇上限 ${g.maxBytes} 位元組，目前 $bytes'),
          kind: ToastKind.warn);
    }
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
        uid: context.read<SessionStore>().uid,
      );
      if (!mounted) return;
      // 失敗就留在這頁，打好的字還在，改一改能直接再送
      if (!r.ok) {
        toast(context, r.message, kind: ToastKind.warn);
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
          // 主題關閉、權限不足、達每日回帖上限…論壇給的原話
          if (_gate case ReplyGate(allowed: false, :final message))
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 11, 18, 11),
              color: scheme.error.withValues(alpha: .1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(LucideIcons.lock, size: 16, color: scheme.error),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sys(message),
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          color: scheme.error),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _ctrl,
              builder: (c, v, _) => _Counter(text: v.text.trim(), gate: _gate),
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
                          onPressed: _busy || _gate?.allowed == false ? null : _submit,
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


/// 字數。論壇是用位元組算的（中文一字 3、英數 1），但使用者想的是「幾個字」：
/// 平常只顯示字數，不夠長／太長時才換算成還差幾個字
class _Counter extends StatelessWidget {
  const _Counter({required this.text, this.gate});
  final String text;
  final ReplyGate? gate;

  @override
  Widget build(BuildContext context) {
    final chars = text.characters.length;
    final bytes = api.postBytes(text);
    final min = gate?.minBytes ?? 0;
    final max = gate?.maxBytes ?? 0;

    var note = '';
    Color? color;
    if (text.isNotEmpty && min > 0 && bytes < min) {
      note = tr('還差約 ${((min - bytes) / 3).ceil()} 字');
      color = Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFF0B14A)
          : const Color(0xFFA35F00);
    } else if (max > 0 && bytes > max) {
      note = tr('超過上限 ${bytes - max} 位元組');
      color = Theme.of(context).colorScheme.error;
    }

    return Row(
      children: [
        Expanded(
          child: min > 0
              ? Text(
                  tr('論壇規定至少 $min 位元組（約 ${(min / 3).ceil()} 個中文字）'),
                  style: TextStyle(fontSize: 11.5, color: faint(context)),
                )
              : const SizedBox.shrink(),
        ),
        Text(
          [tr('$chars 字'), if (note.isNotEmpty) note].join(' · '),
          style: TextStyle(
            fontSize: 12,
            color: color ?? faint(context),
            fontWeight: note.isEmpty ? null : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
