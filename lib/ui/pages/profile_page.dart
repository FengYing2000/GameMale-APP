import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/discuz.dart' as api;
import '../../api/http.dart';
import '../../api/models.dart';
import '../../i18n/ui.dart';
import '../../store/session.dart';
import '../../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/poke_sheet.dart';
import '../widgets/require_login.dart';
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
    if (!await requireLogin(context, action: what)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final r = await run();
      if (mounted) toast(context, r.message);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, tr('$what失敗：${e.message}'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openMedal(Medal m) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CachedNetworkImage(
                  imageUrl: m.image,
                  httpHeaders: Api.imageHeaders,
                  height: 58,
                  errorWidget: (c, _, _) =>
                      const Icon(LucideIcons.medal, size: 40),
                ),
                const SizedBox(height: 14),
                Text(
                  m.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, height: 1.35),
                ),
                if (m.level.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(c).colorScheme.primary.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${tr('等級')} ${m.level}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(c).colorScheme.primary),
                    ),
                  ),
                ],
                if (m.effects.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final e in m.effects)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFF4CAF50)
                                    .withValues(alpha: .35)),
                          ),
                          child: Text(e,
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ],
                if (m.desc.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(c).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      m.desc,
                      style: TextStyle(
                          fontSize: 13.5, height: 1.8, color: subtle(c)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(tr('關閉'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final isMe = context.watch<SessionStore>().uid == widget.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(d?.name.isNotEmpty == true ? d!.name : tr('個人資料')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            ?StateBox.maybe(loading: _loading, error: _err, onRetry: _load),
            if (d != null) ...[
              _header(d, isMe),
              if (d.stats.isNotEmpty) _stats(d),
              if (d.medals.isNotEmpty) _medals(d),
              for (final s in d.sections) _section(s),
              if (d.fields.isNotEmpty)
                _block(tr('詳細資料'), [
                  for (final f in d.fields) _row(f.label, f.value),
                ]),
              if (d.credits.isNotEmpty)
                _block(tr('積分'), [
                  for (final c in d.credits)
                    _row(c.name, c.value, bold: true),
                ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(ProfileData d, bool isMe) {
    final accent = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: Column(
          children: [
            Avatar(d.avatar, size: 68),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (d.online) ...[
                  const Icon(LucideIcons.circle, size: 9, color: Color(0xFF43A047)),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(d.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text('UID ${d.uid}',
                style: TextStyle(fontSize: 12.5, color: faint(context))),
            if (d.level.isNotEmpty || d.roles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  if (d.level.isNotEmpty) _tag(d.level, accent, filled: true),
                  for (final r in d.roles) _tag(r, accent),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/space/${widget.uid}'),
                  icon: const Icon(LucideIcons.user, size: 18),
                  label: Text(tr('個人空間')),
                ),
                if (!isMe) ...[
                  FilledButton.icon(
                    onPressed: () => context.push('/pm/${widget.uid}'),
                    icon: const Icon(LucideIcons.mail, size: 18),
                    label: Text(tr('傳送私訊')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _act(() => api.addFriend(widget.uid), tr('加好友')),
                    icon: const Icon(LucideIcons.userPlus, size: 18),
                    label: Text(tr('加好友')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => showPokeSheet(context, widget.uid,
                            name: _data?.name ?? ''),
                    icon: const Icon(LucideIcons.handHelping, size: 18),
                    label: Text(tr('打招呼')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color accent, {bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: filled ? accent.withValues(alpha: .14) : null,
          border: Border.all(color: accent.withValues(alpha: filled ? 0 : .45)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11.5, color: accent, fontWeight: FontWeight.w600)),
      );

  /// 好友數／記錄數／日誌數／相冊數／回帖數／主題數；數字黏在名稱後面，拆成兩行顯示
  Widget _stats(ProfileData d) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              for (final s in d.stats)
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        _statNumber(s.name),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _statLabel(s.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: faint(context)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _medals(ProfileData d) => _block(
        '${tr('勳章')} · ${d.medals.length}',
        [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in d.medals)
                  InkWell(
                    onTap: () => _openMedal(m),
                    child: CachedNetworkImage(
                      imageUrl: m.image,
                      httpHeaders: Api.imageHeaders,
                      height: 30,
                      errorWidget: (c, _, _) =>
                          const Icon(LucideIcons.medal, size: 26),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );

  Widget _section(ProfileSection s) => _block(s.title, [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in s.links)
                ActionChip(
                  label:
                      Text(l.name, style: const TextStyle(fontSize: 12.5)),
                  visualDensity: VisualDensity.compact,
                  onPressed: l.fid == null
                      ? null
                      // 群組跟版塊是兩套頁面，網址裡看得出來
                      : () => context.push(l.url.contains('group-')
                          ? '/g/${l.fid}'
                          : '/f/${l.fid}'),
                ),
            ],
          ),
        ),
      ]);

  Widget _block(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: faint(context))),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: children),
            ),
          ),
        ],
      );

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: Text(label,
                  style: TextStyle(fontSize: 13.5, color: faint(context))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(value,
                  style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: bold ? FontWeight.w600 : null,
                      color: bold ? subtle(context) : null)),
            ),
          ],
        ),
      );
}

final _statTail = RegExp(r'[\d.]+\s*\S*$');

String _statNumber(String s) => _statTail.firstMatch(s)?.group(0)?.trim() ?? '';

String _statLabel(String s) => s.replaceAll(_statTail, '').trim();
