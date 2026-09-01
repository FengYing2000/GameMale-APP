import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';
import 'package:gm_api/register.dart' as api;
import '../../i18n/ui.dart';
import '../../theme.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

/// 註冊。這站的註冊被 k_qareg 外掛擋在一份考卷後面，
/// 答對之後才會拿到真正的註冊表單（帳號／密碼／信箱／驗證碼）。
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  RegisterQuiz? _quiz;
  bool _loading = true;
  bool _busy = false;
  String? _err;

  /// 欄位名 → 選到的 value
  final _answers = <String, Set<String>>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      final q = await api.fetchRegisterQuiz();
      if (mounted) {
        setState(() {
          _quiz = q;
          _answers.clear();
        });
      }
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final q = _quiz;
    if (q == null) return;

    final unanswered = q.questions
        .where((x) => (_answers[x.field] ?? const {}).isEmpty)
        .length;
    if (unanswered > 0) {
      return toast(context, tr('還有 $unanswered 題沒作答'));
    }

    setState(() => _busy = true);
    try {
      final next = await api.submitRegisterQuiz(
        q.formhash,
        {for (final e in _answers.entries) e.key: e.value.toList()},
      );
      if (!mounted) return;
      setState(() {
        _quiz = next;
        _answers.clear();
      });
      // 題目還在＝沒過。論壇這時候不會另外給錯誤訊息，只是把考卷重洗一份
      toast(
        context,
        next.questions.isEmpty
            ? tr('答題通過，請接著在瀏覽器完成註冊')
            : tr('答案不正確，題目已重新出題'),
      );
      if (next.questions.isEmpty) await _openInBrowser();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('送出失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openInBrowser() => launchUrl(
        Uri.parse('$kOrigin/${api.registerPath}'),
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    final q = _quiz;
    final done = q == null
        ? 0
        : q.questions
            .where((x) => (_answers[x.field] ?? const {}).isNotEmpty)
            .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('註冊帳號')),
        actions: [
          IconButton(
            tooltip: tr('用瀏覽器開啟'),
            icon: const Icon(LucideIcons.externalLink),
            onPressed: _openInBrowser,
          ),
        ],
      ),
      bottomNavigationBar: q == null || q.questions.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _busy || q.closed ? null : _submit,
                  child: Text(q.closed
                      ? tr('目前無法註冊')
                      : '${tr('送出答案')}（$done / ${q.questions.length}）'),
                ),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (q != null) ...[
              if (q.notice.isNotEmpty) _notice(q),
              if (q.questions.isEmpty && !_loading)
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 30, 26, 0),
                  child: Text(
                    tr('這裡沒有拿到題目。註冊流程最後一步要填帳號、信箱與驗證碼，'
                        '請用瀏覽器開啟論壇的註冊頁完成。'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, height: 1.7, color: faint(context)),
                  ),
                ),
              for (var i = 0; i < q.questions.length; i++)
                _question(q.questions[i], i + 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notice(RegisterQuiz q) {
    final c = Theme.of(context).colorScheme;
    final bad = q.closed;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: (bad ? c.error : c.primary).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: (bad ? c.error : c.primary).withValues(alpha: .3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(bad ? LucideIcons.ban : LucideIcons.info,
              size: 20, color: bad ? c.error : c.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(q.notice,
                style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: bad ? c.error : c.primary)),
          ),
        ],
      ),
    );
  }

  Widget _question(QuizQuestion q, int no) {
    final picked = _answers[q.field] ?? const <String>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.title,
                style: const TextStyle(
                    fontSize: 14.5, height: 1.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final o in q.options)
              InkWell(
                onTap: () => setState(() {
                  final set = _answers.putIfAbsent(q.field, () => <String>{});
                  if (q.multi) {
                    set.contains(o.value) ? set.remove(o.value) : set.add(o.value);
                  } else {
                    set
                      ..clear()
                      ..add(o.value);
                  }
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        q.multi
                            ? (picked.contains(o.value)
                                ? LucideIcons.squareCheckBig
                                : LucideIcons.square)
                            : (picked.contains(o.value)
                                ? LucideIcons.circleDot
                                : LucideIcons.circle),
                        size: 20,
                        color: picked.contains(o.value)
                            ? Theme.of(context).colorScheme.primary
                            : faint(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(o.label,
                            style: const TextStyle(fontSize: 14, height: 1.45)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
