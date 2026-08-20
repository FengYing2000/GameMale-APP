import '../../i18n/ui.dart';
import 'package:flutter/material.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
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
                Icon(Icons.poll_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
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
            if (!p.votable)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(tr('這個投票目前不開放作答'),
                    style: TextStyle(fontSize: 13, color: subtle(context))),
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
}
