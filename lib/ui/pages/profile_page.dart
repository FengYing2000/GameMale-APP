import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/models.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/post_body.dart';
import '../widgets/state_box.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.uid});
  final int uid;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  ProfileData? _data;
  bool _loading = true;
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
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Column(
                    children: [
                      Avatar(d.avatar, size: 64),
                      const SizedBox(height: 10),
                      Text(d.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('UID ${d.uid}',
                          style: TextStyle(fontSize: 12.5, color: faint(context))),
                      if (!isMe) ...[
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () => context.push('/pm/${widget.uid}'),
                          icon: const Icon(Icons.mail_outline, size: 18),
                          label: const Text('傳送私訊'),
                        ),
                      ],
                    ],
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
      ),
    );
  }
}
