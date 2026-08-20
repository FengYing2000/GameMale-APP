import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/state_box.dart';
import '../widgets/toast.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.uid});
  final int uid;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ProfileData? _data;
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
      final d = await api.fetchProfile(widget.uid);
      if (mounted) setState(() => _data = d);
    } on DiscuzException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Future<SubmitResult> Function() run, String what) async {
    setState(() => _busy = true);
    try {
      final r = await run();
      if (mounted) toast(context, r.message);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, '$what失敗：${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final isMe = context.watch<SessionStore>().uid == widget.uid;

    return Scaffold(
      appBar: AppBar(title: Text(d?.name.isNotEmpty == true ? d!.name : '個人資料')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                  child: Column(
                    children: [
                      Avatar(d.avatar, size: 68),
                      const SizedBox(height: 10),
                      Text(d.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                        [
                          'UID ${d.uid}',
                          if (d.level.isNotEmpty) d.level,
                        ].join(' · '),
                        style: TextStyle(fontSize: 12.5, color: faint(context)),
                      ),
                      if (!isMe) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: [
                            FilledButton.icon(
                              onPressed: () => context.push('/pm/${widget.uid}'),
                              icon: const Icon(Icons.mail_outline, size: 18),
                              label: const Text('傳送私訊'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _act(() => api.addFriend(widget.uid), '加好友'),
                              icon: const Icon(Icons.person_add_alt, size: 18),
                              label: const Text('加好友'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _act(() => api.poke(widget.uid), '打招呼'),
                              icon: const Icon(Icons.waving_hand_outlined, size: 18),
                              label: const Text('打招呼'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (d.credits.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
                  child: Text('積分',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: faint(context))),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        for (final c in d.credits)
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(c.name, style: const TextStyle(fontSize: 14)),
                            trailing: Text(c.value,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: subtle(context))),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
