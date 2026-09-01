import '../../i18n/ui.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/models.dart';
import '../../theme.dart';
import 'toast.dart';

class PollCard extends StatefulWidget {
  const PollCard({super.key, required this.poll, required this.onVoted});
  final Poll poll;
  final VoidCallback onVoted;

  @override
  State<PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<PollCard> {
  final _picked = <String>{};
  bool _busy = false;

  Future<void> _vote() async {
    if (_picked.isEmpty) return toast(context, tr('請先選擇選項'));
    setState(() => _busy = true);
    try {
      final r = await api.votePoll(widget.poll, _picked.toList());
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) widget.onVoted();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('投票失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.poll;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.chartNoAxesColumn, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Text(p.title.isEmpty ? tr('投票') : p.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            if (p.info.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(p.info, style: TextStyle(fontSize: 12, color: faint(context))),
            ],
            if (p.deadline.isNotEmpty)
              Text(p.deadline, style: TextStyle(fontSize: 12, color: faint(context))),
            const SizedBox(height: 8),
            // 已經投過票的話論壇不給表單，改成把結果攤出來
            if (p.voted)
              for (final o in p.options) _result(context, o, p)
            else if (!p.votable)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  p.status.isNotEmpty ? p.status : tr('這個投票目前不開放作答'),
                  style: TextStyle(fontSize: 13, color: subtle(context)),
                ),
              )
            else if (p.multiple)
              for (final o in p.options)
                CheckboxListTile(
                  value: _picked.contains(o.id),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(o.text, style: const TextStyle(fontSize: 14)),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _picked.add(o.id);
                    } else {
                      _picked.remove(o.id);
                    }
                  }),
                )
            else
              // 單選要有 RadioGroup 才點得動（Flutter 3.32 起的 API）
              RadioGroup<String>(
                groupValue: _picked.isEmpty ? null : _picked.first,
                onChanged: (v) => setState(() {
                  _picked
                    ..clear()
                    ..addAll(v == null ? const <String>[] : [v]);
                }),
                child: Column(
                  children: [
                    for (final o in p.options)
                      RadioListTile<String>(
                        value: o.id,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(o.text, style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                ),
              ),
            if (p.voted && p.status.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(LucideIcons.vote,
                      size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(p.status,
                        style: TextStyle(fontSize: 12.5, color: subtle(context))),
                  ),
                ],
              ),
            ],
            if (p.votable) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _vote,
                  child: Text(_busy ? tr('送出中…') : tr('投票')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 一列結果：選項名 + 進度條 + 百分比與票數
  Widget _result(BuildContext context, PollOption o, Poll p) {
    final pct = double.tryParse(o.percent.replaceAll('%', '')) ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(o.text,
                    style: const TextStyle(fontSize: 14, height: 1.35)),
              ),
              const SizedBox(width: 10),
              Text(
                o.percent.isEmpty ? '' : '${o.percent}　${o.votes}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: subtle(context)),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 6,
              backgroundColor: scheme.onSurface.withValues(alpha: .08),
            ),
          ),
        ],
      ),
    );
  }
}
