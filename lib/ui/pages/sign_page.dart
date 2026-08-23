import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/post_body.dart';
import '../widgets/require_login.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class SignPage extends StatefulWidget {
  const SignPage({super.key});

  @override
  State<SignPage> createState() => _SignPageState();
}

class _SignPageState extends State<SignPage> {
  SignResult? _data;
  bool _loading = true;
  bool _busy = false;
  String? _err;

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
      final d = await api.fetchSignPage();
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sign() async {
    if (!await requireLogin(context, action: tr('簽到'))) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final r = await api.doSign();
      if (!mounted) return;
      toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
      await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('簽到失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final session = context.watch<SessionStore>();

    return Scaffold(
      appBar: AppBar(title: Text(tr('每日簽到'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null) ...[
              _card(d, session),
              // 解不出結構化欄位時才退回原始 HTML
              if (d.stats.isEmpty && d.html.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: PostBody(
                      d.html,
                      textStyle: const TextStyle(fontSize: 14, height: 1.6),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(SignResult d, SessionStore session) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: .22),
                  scheme.primary.withValues(alpha: .06),
                ],
              ),
            ),
            child: Column(
              children: [
                Avatar(session.avatar, size: 62),
                const SizedBox(height: 10),
                Text(
                  session.name.isEmpty ? tr('尚未登入') : session.name,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (d.level.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: .16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(d.level,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.primary)),
                  ),
                ],
              ],
            ),
          ),
          if (d.stats.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                children: [
                  for (final s in d.stats)
                    Expanded(
                      child: Column(
                        children: [
                          Text(s.value,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(s.label,
                              style: TextStyle(
                                  fontSize: 11.5, color: faint(context))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 46,
              child: d.signed
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: Text(tr('今天已經簽到了')),
                    )
                  : FilledButton.icon(
                      onPressed: _busy ? null : _sign,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.event_available, size: 19),
                      label: Text(_busy ? tr('簽到中…') : tr('立即簽到')),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
