import '../../i18n/ui.dart';
import '../widgets/require_login.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../theme.dart';
import '../../store/session.dart';
import '../widgets/composer_toolbar.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class NewThreadPage extends StatefulWidget {
  const NewThreadPage({super.key, required this.fid});
  final int fid;

  @override
  State<NewThreadPage> createState() => _NewThreadPageState();
}

class _NewThreadPageState extends State<NewThreadPage> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _messageFocus = FocusNode();
  NewThreadMeta? _meta;
  int? _typeid;
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
    _subject.dispose();
    _message.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await api.newThreadMeta(widget.fid);
      if (!mounted) return;
      setState(() {
        _meta = m;
        if (!m.canPost) _err = m.message ?? tr('這個板塊不允許你發表主題');
      });
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!await requireLogin(context, action: tr('發表主題'))) return;
    if (!mounted) return;
    if (_subject.text.trim().isEmpty) return toast(context, tr('請填標題'));
    if (_message.text.trim().isEmpty) return toast(context, tr('請填內容'));
    if ((_meta?.types.isNotEmpty ?? false) && _typeid == null) {
      return toast(context, tr('請選擇主題分類'));
    }

    setState(() => _busy = true);
    try {
      final r = await api.newThread(
        fid: widget.fid,
        subject: _subject.text.trim(),
        message: _message.text.trim(),
        typeid: _typeid?.toString() ?? '',
      );
      if (!mounted) return;
      if (!r.ok) {
        toast(context, r.message);
        return;
      }
      final uid = context.read<SessionStore>().uid;
      final credits = await api.consumeCreditNotice(uid: uid);
      final rule = await api.consumeCreditRule();
      if (!mounted) return;
      toastCredits(
        context,
        message: r.message,
        rule: rule,
        credits: credits,
      );
      Navigator.of(context).pop(true);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('發表失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('發表新主題')),
        actions: [
          TextButton(
            onPressed: (_busy || _loading || _err != null) ? null : _submit,
            child: Text(_busy ? tr('送出中') : tr('發表')),
          ),
        ],
      ),
      body: (_loading || _err != null)
          ? StateBox(loading: _loading, error: _err)
          : ListView(
              children: [
                Card(
                  child: Column(
                    children: [
                      if (meta != null && meta.types.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('主題分類'),
                                  style: TextStyle(fontSize: 12, color: faint(context))),
                              DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _typeid,
                                  isExpanded: true,
                                  hint: Text(tr('請選擇')),
                                  items: meta.types
                                      .map((t) => DropdownMenuItem(
                                          value: t.typeid, child: Text(t.name)))
                                      .toList(),
                                  onChanged: (v) => setState(() => _typeid = v),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(indent: 14, endIndent: 14),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: TextField(
                          controller: _subject,
                          maxLength: 80,
                          decoration: InputDecoration(
                            labelText: tr('標題'),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      const Divider(indent: 14, endIndent: 14),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        child: TextField(
                          controller: _message,
                          focusNode: _messageFocus,
                          maxLines: 12,
                          minLines: 8,
                          decoration: InputDecoration(
                            labelText: tr('內容'),
                            hintText: tr('支援 Discuz BBCode'),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      const Divider(indent: 14, endIndent: 14),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ComposerToolbar(
                            controller: _message, focus: _messageFocus),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
