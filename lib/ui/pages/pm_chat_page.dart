import 'package:flutter/material.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../widgets/post_body.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class PmChatPage extends StatefulWidget {
  const PmChatPage({super.key, required this.touid});
  final int touid;

  @override
  State<PmChatPage> createState() => _PmChatPageState();
}

class _PmChatPageState extends State<PmChatPage> {
  final _ctrl = TextEditingController();
  List<PmMessage>? _msgs;
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final m = await api.fetchPmChat(widget.touid);
      if (mounted) setState(() => _msgs = m);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _busy = true);
    try {
      final r = await api.sendPm(widget.touid, text);
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) {
        _ctrl.clear();
        await _load();
      }
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '傳送失敗：${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final msgs = _msgs;

    return Scaffold(
      appBar: AppBar(title: const Text('私人訊息')),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  ?StateBox.maybe(
                    loading: _loading,
                    error: _err,
                    empty: !_loading && _err == null && (msgs?.isEmpty ?? false),
                    emptyText: '還沒有訊息',
                    onRetry: _load,
                  ),
                  if (msgs != null && msgs.isNotEmpty)
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < msgs.length; i++) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                              child: PostBody(
                                msgs[i].html,
                                textStyle: const TextStyle(fontSize: 14, height: 1.6),
                              ),
                            ),
                            if (i != msgs.length - 1) const Divider(indent: 14, endIndent: 14),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SafeArea(
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
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: '輸入訊息…',
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
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: Text(_busy ? '…' : '送出'),
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
