import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
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
  final _scroll = ScrollController();
  PmChat? _chat;
  bool _loading = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool toBottom = true}) async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final c = await api.fetchPmChat(widget.touid);
      if (!mounted) return;
      setState(() => _chat = c);
      if (toBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(_scroll.position.maxScrollExtent);
          }
        });
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      final r = await api.sendPm(
        widget.touid,
        text,
        pmid: _chat?.pmid ?? '',
        formhash: _chat?.formhash ?? '',
      );
      if (!mounted) return;
      if (r.ok) {
        _ctrl.clear();
        await _load();
      } else {
        toast(context, r.message);
      }
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('傳送失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final msgs = chat?.messages ?? const <PmMessage>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name.isNotEmpty ? widget.name : tr('私人訊息')),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: tr('個人資料'),
            onPressed: () => context.push('/u/${widget.touid}'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(toBottom: false),
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  ?StateBox.maybe(
                    loading: _loading,
                    error: _err,
                    empty: !_loading && _err == null && msgs.isEmpty,
                    emptyText: tr('還沒有訊息'),
                    onRetry: _load,
                  ),
                  for (final m in msgs)
                    _Bubble(
                      msg: m,
                      onTapAvatar: m.mine
                          ? null
                          : () => context.push('/u/${widget.touid}'),
                    ),
                ],
              ),
            ),
          ),
          _Composer(ctrl: _ctrl, busy: _busy, onSend: _send),
        ],
      ),
    );
  }
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
        crossAxisAlignment:
            msg.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
              child: Text(msg.time,
                  style: TextStyle(fontSize: 11, color: faint(context))),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Row(
        mainAxisAlignment:
            msg.mine ? MainAxisAlignment.end : MainAxisAlignment.start,
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
  const _Composer({required this.ctrl, required this.busy, required this.onSend});
  final TextEditingController ctrl;
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
          border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: tr('輸入訊息…'),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
              icon: busy
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
