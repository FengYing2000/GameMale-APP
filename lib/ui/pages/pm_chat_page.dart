import 'dart:convert' show HtmlEscape;

import '../../i18n/ui.dart';
import '../widgets/require_login.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/models.dart';

import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/composer_toolbar.dart';
import '../widgets/post_body.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class PmChatPage extends StatefulWidget {
  const PmChatPage({super.key, required this.touid, this.name = ''});
  final int touid;

  /// 從列表帶過來的對方暱稱；論壇的頁面標題只有「查看消息」
  final String name;

  @override
  State<PmChatPage> createState() => _PmChatPageState();
}

class _PmChatPageState extends State<PmChatPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  PmChat? _chat;
  bool _loading = true;
  bool _busy = false;
  String? _err;

  /// 剛送出的訊息：先畫出來，不用等論壇回應。重抓的對話裡出現同一則之後就拿掉
  final _outgoing = <_Outgoing>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// [silent]：送出之後在背景重抓，不要把畫面換成轉圈
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _err = null;
      });
    }
    try {
      final c = await api.fetchPmChat(widget.touid);
      if (!mounted) return;
      setState(() {
        _chat = c;
        _outgoing.removeWhere((o) => o.sent && _serverHas(c, o.text));
      });
    } on DiscuzException catch (e) {
      if (mounted && !silent) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 論壇的對話最後幾則裡有沒有這段。比對時忽略空白：換行在網頁上會變成 <br>
  static bool _serverHas(PmChat c, String text) {
    String norm(String s) => s.replaceAll(RegExp(r'\s+'), '');
    final want = norm(text);
    final mine = c.messages.where((m) => m.mine).toList();
    return mine.reversed.take(5).any((m) => norm(m.text) == want);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy) return;
    if (!await requireLogin(context, action: tr('傳送私訊'))) return;
    if (!mounted) return;

    final out = _Outgoing(text);
    setState(() {
      _outgoing.add(out);
      _ctrl.clear();
      _busy = true;
    });
    _toLatest();
    try {
      final r = await api.sendPm(
        widget.touid,
        text,
        pmid: _chat?.pmid ?? '',
        formhash: _chat?.formhash ?? '',
      );
      if (!mounted) return;
      if (!r.ok) {
        _undo(out, text);
        toast(context, r.message);
        return;
      }
      setState(() => out.sent = true);
      await _load(silent: true);
    } on DiscuzException catch (e) {
      if (!mounted) return;
      _undo(out, text);
      toast(context, tr('傳送失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 送不出去：氣泡拿掉、字放回輸入框，改一改能直接再送
  void _undo(_Outgoing out, String text) {
    setState(() {
      _outgoing.remove(out);
      if (_ctrl.text.isEmpty) _ctrl.text = text;
    });
  }

  /// 列表是倒著排的（最新的在最下面＝捲動位置 0），回到 0 就是最新
  void _toLatest() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final msgs = chat?.messages ?? const <PmMessage>[];
    final me = context.watch<SessionStore>().avatar;
    // 倒著排：第 0 個是最新的。剛送出的比論壇回來的更新，排在前面
    final items = <(PmMessage, _Outgoing?)>[
      for (final o in _outgoing.reversed)
        (
          PmMessage(
            html: const HtmlEscape().convert(o.text).replaceAll('\n', '<br>'),
            text: o.text,
            avatar: me,
            time: o.sent ? tr('剛剛') : tr('傳送中…'),
            mine: true,
          ),
          o,
        ),
      for (final m in msgs.reversed) (m, null),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name.isNotEmpty ? widget.name : tr('私人訊息')),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            tooltip: tr('重新整理'),
            onPressed: _loading ? null : () => _load(),
          ),
          IconButton(
            icon: const Icon(LucideIcons.circleUserRound),
            tooltip: tr('個人資料'),
            onPressed: () => context.push('/u/${widget.touid}'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: items.isEmpty
                ? ListView(
                    children: [
                      ?StateBox.maybe(
                        loading: _loading,
                        error: _err,
                        empty: !_loading && _err == null,
                        emptyText: tr('還沒有訊息'),
                        onRetry: _load,
                      ),
                    ],
                  )
                // 點一下訊息區收鍵盤；用滑的不收（往上看訊息時鍵盤還在）
                : GestureDetector(
                    onTap: _focus.unfocus,
                    // 倒著排：鍵盤彈出、可視區變矮時，最新的訊息一樣貼在輸入框上方，
                    // 不會被推到鍵盤後面。以前是從上往下排、載入後再「捲到最底」，
                    // 那一下發生在訊息排版完成之前，停在新訊息上面一點，
                    // 剛送出的訊息就躲在鍵盤後面，看起來像沒送出去
                    child: ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final (m, out) = items[i];
                        final bubble = _Bubble(
                          msg: m,
                          onTapAvatar: m.mine
                              ? null
                              : () => context.push('/u/${widget.touid}'),
                        );
                        return out != null && !out.sent
                            ? Opacity(opacity: .6, child: bubble)
                            : bubble;
                      },
                    ),
                  ),
          ),
          _Composer(ctrl: _ctrl, focus: _focus, busy: _busy, onSend: _send),
        ],
      ),
    );
  }
}

class _Outgoing {
  _Outgoing(this.text);
  final String text;

  /// 論壇回應成功了，等重抓的對話裡出現就換成正式的
  bool sent = false;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, this.onTapAvatar});
  final PmMessage msg;
  final VoidCallback? onTapAvatar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = msg.mine
        ? brand.withValues(alpha: 0.18)
        : scheme.onSurface.withValues(alpha: 0.06);

    final bubble = Flexible(
      child: Column(
        crossAxisAlignment: msg.mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(14),
                topRight: const Radius.circular(14),
                bottomLeft: Radius.circular(msg.mine ? 14 : 3),
                bottomRight: Radius.circular(msg.mine ? 3 : 14),
              ),
            ),
            child: PostBody(
              msg.html,
              textStyle: const TextStyle(fontSize: 14.5, height: 1.55),
            ),
          ),
          if (msg.time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 4, right: 4),
              child: Text(
                msg.time,
                style: TextStyle(fontSize: 11, color: faint(context)),
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Row(
        mainAxisAlignment: msg.mine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: msg.mine
            ? [
                const SizedBox(width: 48),
                bubble,
                const SizedBox(width: 8),
                Avatar(msg.avatar, size: 32, onTap: onTapAvatar),
              ]
            : [
                Avatar(msg.avatar, size: 32, onTap: onTapAvatar),
                const SizedBox(width: 8),
                bubble,
                const SizedBox(width: 48),
              ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.ctrl,
    required this.focus,
    required this.busy,
    required this.onSend,
  });
  final TextEditingController ctrl;
  final FocusNode focus;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // BBCode 與表情，跟網頁版私訊的編輯器一樣。只在打字時出現，看訊息時不佔位置
            ListenableBuilder(
              listenable: focus,
              builder: (context, _) => focus.hasFocus
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ComposerToolbar(
                        controller: ctrl,
                        focus: focus,
                        pm: true,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: ctrl,
                    focusNode: focus,
                    // 鍵盤的 Return 是換行，送出用右邊的按鈕
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    // 網頁版預設「碰到輸入框外面就收鍵盤」，連滑動訊息都算
                    onTapOutside: (_) {},
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: tr('輸入訊息…'),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.05),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: busy ? null : onSend,
                  tooltip: tr('傳送'),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.send, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
