import 'package:flutter/material.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import 'require_login.dart';
import 'smart_image.dart';
import 'toast.dart';

/// 打招呼。論壇是一張表單：14 種動作挑一個，再選填一句話（最多 10 字）。
/// 動作清單直接讀論壇的表單，不寫死。
///
/// [fromNotice] 是從提醒頁回招呼，送出後論壇會順手清掉那則提醒。
/// 送出成功回 true。
Future<bool> showPokeSheet(
  BuildContext context,
  int uid, {
  String name = '',
  bool fromNotice = false,
}) async {
  if (!await requireLogin(context, action: tr('打招呼'))) return false;
  if (!context.mounted) return false;

  PokeForm form;
  try {
    form = await api.fetchPokeForm(uid);
  } on DiscuzException catch (e) {
    if (context.mounted) toast(context, '${tr('拿不到打招呼的選項：')}${e.message}');
    return false;
  }
  if (!context.mounted) return false;
  if (!form.ready) {
    toast(context, tr('拿不到打招呼的選項'), kind: ToastKind.warn);
    return false;
  }

  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => _PokeSheet(form: form, name: name, fromNotice: fromNotice),
  );
  return ok == true;
}

class _PokeSheet extends StatefulWidget {
  const _PokeSheet({
    required this.form,
    required this.name,
    required this.fromNotice,
  });
  final PokeForm form;
  final String name;
  final bool fromNotice;

  @override
  State<_PokeSheet> createState() => _PokeSheetState();
}

class _PokeSheetState extends State<_PokeSheet> {
  late int _iconId = widget.form.defaultIconId;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final r = await api.sendPoke(
        widget.form.uid,
        iconId: _iconId,
        note: _note.text.trim(),
        formhash: widget.form.formhash,
        fromNotice: widget.fromNotice,
      );
      if (!mounted) return;
      Navigator.pop(context, r.ok);
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
    } on DiscuzException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, '${tr('打招呼失敗：')}${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          18, 0, 18, MediaQuery.of(context).viewInsets.bottom + 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.name.isEmpty
                ? tr('打個招呼')
                : '${tr('向')} ${widget.name} ${tr('打個招呼')}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * .38),
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final o in widget.form.options)
                    ChoiceChip(
                      selected: _iconId == o.id,
                      onSelected: (_) => setState(() => _iconId = o.id),
                      avatar: o.icon.isEmpty
                          ? null
                          : SmartImage(src: o.icon, width: 18, height: 18),
                      label: Text(o.name, style: const TextStyle(fontSize: 13)),
                      side: _iconId == o.id
                          ? BorderSide(color: accent, width: 1.4)
                          : null,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 10,
            decoration: InputDecoration(
              labelText: tr('想說的話（可留空）'),
              border: const OutlineInputBorder(),
              counterText: '',
            ),
          ),
          if (widget.form.noteHint.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.form.noteHint,
                style: TextStyle(fontSize: 11.5, color: faint(context))),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _send,
              child: Text(_busy ? '…' : tr('送出')),
            ),
          ),
        ],
      ),
    );
  }
}
