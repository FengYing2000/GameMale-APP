import 'package:flutter/material.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../widgets/post_body.dart';
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
    setState(() => _busy = true);
    try {
      final r = await api.doSign();
      if (mounted) toast(context, r.message);
      await _load();
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '簽到失敗：${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;

    return Scaffold(
      appBar: AppBar(title: const Text('每日簽到')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
          if (d != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: (_busy || d.signed) ? null : _sign,
                  child: Text(_busy ? '簽到中…' : (d.signed ? '今天已經簽到了' : '立即簽到')),
                ),
              ),
            ),
            if (d.html.isNotEmpty)
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
    );
  }
}
