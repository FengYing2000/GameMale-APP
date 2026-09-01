import 'package:flutter/material.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/composer_toolbar.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

/// 編輯自己的帖子或回覆。論壇回的是原始 BBCode，直接讓使用者改。
class EditPostPage extends StatefulWidget {
  const EditPostPage({
    super.key,
    required this.fid,
    required this.tid,
    required this.pid,
  });

  final int fid;
  final int tid;
  final int pid;

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _messageFocus = FocusNode();
  EditForm? _form;
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
      final f = await api.fetchEditForm(
          fid: widget.fid, tid: widget.tid, pid: widget.pid);
      if (!mounted) return;
      setState(() {
        _form = f;
        _subject.text = f.subject;
        _message.text = f.message;
        if (!f.canEdit) _err = f.message2 ?? tr('沒有權限編輯這一篇');
      });
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final f = _form;
    if (f == null) return;
    if (_message.text.trim().isEmpty) return toast(context, tr('內容不能空白'));

    setState(() => _busy = true);
    try {
      final r = await api.submitEdit(
        form: f,
        message: _message.text.trim(),
        subject: _subject.text.trim(),
      );
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) Navigator.of(context).pop(true);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '${tr('編輯失敗')}：${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _form;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('編輯')),
        actions: [
          TextButton(
            onPressed: (_busy || _loading || _err != null) ? null : _submit,
            child: Text(_busy ? tr('儲存中') : tr('儲存')),
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
                      if (f?.hasSubject ?? false) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          child: TextField(
                            controller: _subject,
                            decoration: InputDecoration(
                              labelText: tr('標題'),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        const Divider(indent: 14, endIndent: 14),
                      ],
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        child: TextField(
                          controller: _message,
                          focusNode: _messageFocus,
                          maxLines: 18,
                          minLines: 10,
                          decoration: InputDecoration(
                            labelText: tr('內容'),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  child: Text(
                    tr('這裡顯示的是原始 BBCode，和你在論壇上編輯時看到的一樣。'),
                    style: TextStyle(fontSize: 12.5, height: 1.6, color: faint(context)),
                  ),
                ),
              ],
            ),
    );
  }
}
