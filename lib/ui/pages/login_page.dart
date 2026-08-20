import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/toast.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _answer = TextEditingController();
  final _seccode = TextEditingController();

  LoginMeta? _meta;
  String _questionid = '0';
  bool _loadingMeta = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _answer.dispose();
    _seccode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingMeta = true;
      _err = null;
    });
    try {
      final m = await api.loginMeta();
      if (!mounted) return;
      setState(() => _meta = m);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _refreshCaptcha() async {
    final hash = _meta?.seccodehash;
    if (hash == null || hash.isEmpty) return;
    try {
      final img = await api.seccodeImage(hash);
      if (!mounted) return;
      setState(() {
        _meta = _meta!.withImage(img);
        _seccode.clear();
      });
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      return toast(context, '請輸入帳號與密碼');
    }
    final meta = _meta;
    if (meta == null) return;

    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final res = await api.login(
        username: _user.text.trim(),
        password: _pass.text,
        meta: meta,
        questionid: _questionid,
        answer: _answer.text,
        seccode: _seccode.text.trim(),
      );
      if (!res.ok) {
        if (mounted) setState(() => _err = res.message);
        await _refreshCaptcha();
        return;
      }
      final user = await api.checkSession();
      if (!mounted) return;
      if (user != null) context.read<SessionStore>().applyUser(user);
      toast(context, '登入成功');
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = _meta;

    return Scaffold(
      appBar: AppBar(title: const Text('登入 GameMale')),
      body: _loadingMeta
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : ListView(
              children: [
                Card(
                  child: Column(
                    children: [
                      _field(
                        label: '使用者名稱 / Email',
                        child: TextField(
                          controller: _user,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          decoration: _dec('請輸入帳號'),
                        ),
                      ),
                      const Divider(indent: 14, endIndent: 14),
                      _field(
                        label: '密碼',
                        child: TextField(
                          controller: _pass,
                          obscureText: true,
                          decoration: _dec('請輸入密碼'),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      if ((meta?.questions.length ?? 0) > 1) ...[
                        const Divider(indent: 14, endIndent: 14),
                        _field(
                          label: '安全提問',
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _questionid,
                              isExpanded: true,
                              items: meta!.questions
                                  .map((q) => DropdownMenuItem(value: q.id, child: Text(q.name)))
                                  .toList(),
                              onChanged: (v) => setState(() => _questionid = v ?? '0'),
                            ),
                          ),
                        ),
                      ],
                      if (_questionid != '0') ...[
                        const Divider(indent: 14, endIndent: 14),
                        _field(
                          label: '提問答案',
                          child: TextField(controller: _answer, decoration: _dec('安全提問的答案')),
                        ),
                      ],
                      if (meta?.needSeccode ?? false) ...[
                        const Divider(indent: 14, endIndent: 14),
                        _field(
                          label: '驗證碼（點圖片可換一張）',
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _seccode,
                                  autocorrect: false,
                                  decoration: _dec('輸入圖中字元'),
                                  onSubmitted: (_) => _submit(),
                                ),
                              ),
                              const SizedBox(width: 10),
                              GestureDetector(
                                onTap: _refreshCaptcha,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: meta?.seccodeImage != null
                                      ? Image.memory(meta!.seccodeImage!, height: 34)
                                      : Container(
                                          width: 90,
                                          height: 34,
                                          color: Colors.black12,
                                          alignment: Alignment.center,
                                          child: const Icon(Icons.refresh, size: 18),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_err != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                    child: Text(_err!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error, fontSize: 13, height: 1.5)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_busy ? '登入中…' : '登入'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(26, 12, 26, 30),
                  child: Text(
                    '帳號密碼只會送到 www.gamemale.com。登入後 Cookie 會保存在本機，'
                    '通常可維持 30 天，過期後會自動回到這一頁。',
                    style: TextStyle(fontSize: 12.5, height: 1.6, color: faint(context)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field({required String label, required Widget child}) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: faint(context))),
            const SizedBox(height: 2),
            child,
          ],
        ),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      );
}
