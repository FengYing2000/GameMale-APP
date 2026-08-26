import 'package:flutter/material.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import 'require_login.dart';
import 'smart_image.dart';
import 'toast.dart';

/// 道具的購買／使用彈窗。補簽卡、帖子的提升泵／亮色刷都走這裡。
///
/// [url] 是論壇那顆連結的網址（buy 或 use）。論壇會依你有沒有這個道具
/// 回「使用」或「購買」表單，這裡照它回的內容顯示，不自己猜。
/// 送出成功回 true。
Future<bool> showMagicOp(
  BuildContext context,
  String url, {
  String action = '使用道具',
}) async {
  if (!await requireLogin(context, action: action)) return false;
  if (!context.mounted) return false;

  MagicOp op;
  try {
    op = await api.fetchMagicOp(url);
  } on DiscuzException catch (e) {
    if (context.mounted) toast(context, '${tr('拿不到道具資訊：')}${e.message}');
    return false;
  }
  if (!context.mounted) return false;
  if (!op.ready) {
    toast(context, op.error ?? tr('拿不到道具資訊'), kind: ToastKind.warn);
    return false;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => _MagicSheet(op: op),
  );
  return ok == true;
}

class _MagicSheet extends StatefulWidget {
  const _MagicSheet({required this.op});
  final MagicOp op;

  @override
  State<_MagicSheet> createState() => _MagicSheetState();
}

class _MagicSheetState extends State<_MagicSheet> {
  int _num = 1;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final r = await api.submitMagicOp(widget.op, num: _num);
      if (!mounted) return;
      Navigator.pop(context, r.ok);
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
    } on DiscuzException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      toast(context, '${tr('送出失敗：')}${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final op = widget.op;
    final buying = op.operation != 'use';
    return AlertDialog(
      title: Text(buying ? tr('購買道具') : tr('使用道具')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (op.icon.isNotEmpty) ...[
                SmartImage(src: op.icon, width: 40, height: 40),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(op.name,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.4)),
              ),
            ],
          ),
          if (op.lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final l in op.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(l,
                    style: TextStyle(fontSize: 13, height: 1.5, color: subtle(context))),
              ),
          ],
          if (op.hasNum) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(tr('數量'),
                    style: TextStyle(fontSize: 13, color: faint(context))),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      _num > 1 ? () => setState(() => _num--) : null,
                  icon: const Icon(Icons.remove_circle_outline, size: 22),
                ),
                Text('$_num',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _num++),
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(tr('取消'))),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? '…' : (buying ? tr('確認購買') : tr('確認使用'))),
        ),
      ],
    );
  }
}
