import '../../i18n/ui.dart';
import 'require_login.dart';
import 'package:flutter/material.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../theme.dart';
import 'avatar.dart';
import 'toast.dart';

/// 一鍵評分的預設組合。數值是「想給的分」，實際會被論壇允許的上限夾住，
/// 缺少的項目直接跳過 —— 低等級帳號常常只有其中一兩項。
const _presets = <({String label, int blood, int follow, int fall, String reason})>[
  (label: '超讚', blood: 5, follow: 1, fall: 1, reason: '非常精彩！'),
  (label: '很棒', blood: 3, follow: 1, fall: 1, reason: '內容不錯'),
  (label: '喜歡', blood: 1, follow: 1, fall: 1, reason: '感謝分享！'),
];

Future<bool> showRateSheet(
  BuildContext context, {
  required int fid,
  required int tid,
  required int pid,
}) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _RateSheet(fid: fid, tid: tid, pid: pid),
    ),
  );
  return done ?? false;
}

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.fid, required this.tid, required this.pid});
  final int fid;
  final int tid;
  final int pid;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  RateForm? _form;
  final _scores = <String, int>{};
  final _reason = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _notify = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final f = await api.fetchRateForm(fid: widget.fid, tid: widget.tid, pid: widget.pid);
      if (mounted) setState(() => _form = f);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 預設組合：只套用實際存在的項目，並夾在論壇允許的範圍內
  void _applyPreset(({String label, int blood, int follow, int fall, String reason}) p) {
    final want = {'score3': p.blood, 'score4': p.follow, 'score8': p.fall};
    setState(() {
      _scores.clear();
      for (final o in _form!.options) {
        final w = want[o.field];
        if (w == null || o.choices.isEmpty) continue;
        final max = o.choices.last;
        _scores[o.field] = w > max ? max : w;
      }
      _reason.text = p.reason;
    });
  }

  Future<void> _submit() async {
    final f = _form;
    if (f == null) return;
    if (!await requireLogin(context, action: tr('評分'))) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final r = await api.submitRate(
        form: f,
        scores: _scores,
        reason: _reason.text.trim(),
        notifyAuthor: _notify,
      );
      if (!mounted) return;
      toast(context, r.message);
      if (r.ok) Navigator.pop(context, true);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('評分失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _form;

    if (_loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
      );
    }
    if (_err != null || f == null || !f.canRate) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 32, color: faint(context)),
            const SizedBox(height: 10),
            Text(
              _err ?? f?.message ?? tr('目前不能評分'),
              textAlign: TextAlign.center,
              style: TextStyle(color: subtle(context)),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tr('評分'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            children: [
              for (final p in _presets)
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 15),
                  label: Text(tr(p.label)),
                  onPressed: () => _applyPreset(p),
                ),
            ],
          ),
          const SizedBox(height: 6),

          for (final o in f.options) _optionRow(o),

          const SizedBox(height: 10),
          if (f.reasons.isNotEmpty) ...[
            Text(tr('可選理由'), style: TextStyle(fontSize: 12, color: faint(context))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final r in f.reasons)
                  ActionChip(
                    label: Text(r, style: const TextStyle(fontSize: 12.5)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _reason.text = r),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _reason,
            decoration: InputDecoration(
              labelText: tr('評分理由'),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            value: _notify,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(tr('通知作者'), style: TextStyle(fontSize: 14)),
            onChanged: (v) => setState(() => _notify = v ?? false),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? tr('送出中…') : tr('確定')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionRow(RateOption o) {
    final cur = _scores[o.field] ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(o.name, style: const TextStyle(fontSize: 14)),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('0'),
                  selected: cur == 0,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _scores[o.field] = 0),
                ),
                for (final c in o.choices)
                  ChoiceChip(
                    label: Text('+$c'),
                    selected: cur == c,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _scores[o.field] = c),
                  ),
              ],
            ),
          ),
          Text(
            o.remaining.isEmpty ? '' : '剩 ${o.remaining}',
            style: TextStyle(fontSize: 11, color: faint(context)),
          ),
        ],
      ),
    );
  }
}

/// 已有的評分紀錄
Future<void> showRatings(BuildContext context, {required int tid, required int pid}) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => FutureBuilder<List<RateRecord>>(
      future: api.fetchRatings(tid: tid, pid: pid),
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        }
        final list = snap.data ?? const <RateRecord>[];
        if (list.isEmpty) {
          return SizedBox(
            height: 160,
            child: Center(
              child: Text(tr('這一樓還沒有評分'), style: TextStyle(color: faint(c))),
            ),
          );
        }
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.7),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('評分紀錄（${list.length}）',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final r in list)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (r.uid != null) ...[
                        Avatar(
                          'https://www.gamemale.com/uc_server/avatar.php?uid=${r.uid}&size=small',
                          size: 30,
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(r.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14, fontWeight: FontWeight.w600)),
                                ),
                                Text(r.time,
                                    style: TextStyle(fontSize: 11, color: faint(c))),
                              ],
                            ),
                            const SizedBox(height: 3),
                            // 同一次評分的多項積分排在同一行
                            Wrap(
                              spacing: 10,
                              runSpacing: 2,
                              children: [
                                for (final credit in r.credits)
                                  Text(credit,
                                      style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(c).colorScheme.primary)),
                              ],
                            ),
                            if (r.reason.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(r.reason,
                                  style: TextStyle(fontSize: 12.5, color: subtle(c))),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
