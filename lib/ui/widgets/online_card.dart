import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/discuz.dart' as api;
import 'package:gm_api/http.dart';
import 'package:gm_api/models.dart';
import '../../i18n/ui.dart';
import '../../theme.dart';
import 'net_image.dart';

/// 首頁底部的在線會員。
///
/// **預設收起**——線上常常三百多人，攤開會把首頁灌爆。
///
/// 名單只有登入之後、而且論壇那邊是展開狀態才拿得到，所以首頁那份通常
/// 只有總人數。使用者真的要看時才另外去抓（`showoldetails=yes`），
/// 不必為了它每次都拉一份大頁面。
class OnlineCard extends StatefulWidget {
  const OnlineCard({super.key, required this.info});
  final OnlineInfo info;

  @override
  State<OnlineCard> createState() => _OnlineCardState();
}

class _OnlineCardState extends State<OnlineCard> {
  bool _open = false;
  bool _loading = false;
  OnlineInfo? _detail;

  OnlineInfo get _info => _detail ?? widget.info;

  Future<void> _toggle() async {
    if (_open) {
      setState(() => _open = false);
      return;
    }
    setState(() => _open = true);
    if (_detail != null || _loading) return;
    setState(() => _loading = true);
    try {
      final d = await api.fetchOnlineDetails();
      if (mounted) setState(() => _detail = d);
    } on DiscuzException {
      // 抓不到就維持只有數字，不要把整張卡變成錯誤訊息
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 身分的排序與樣式。
  ///
  /// 論壇用不同顏色的小圖示區分身分。全部混在一起排的話看起來很亂，
  /// 也找不到管理團隊，所以照身分由高到低分組。
  static const _ranks = <String, ({int order, String label, Color color})>{
    'admin': (order: 0, label: '管理員', color: Color(0xFFE05A4E)),
    'supermod': (order: 1, label: '超級版主', color: Color(0xFF3E8ED0)),
    'moderator': (order: 2, label: '版主', color: Color(0xFF48A868)),
    'member': (order: 3, label: '會員', color: Color(0xFF8E8E93)),
  };

  static ({int order, String label, Color color}) _rankOf(String g) =>
      _ranks[g] ?? _ranks['member']!;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = _info;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(LucideIcons.users, color: scheme.primary),
            title: Text(
              '${tr('在線會員')} ${info.total}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            // 論壇收合時只給總人數，沒有細分——那時顯示「會員 0 · 訪客 0」
            // 是錯的，整行不要出現
            subtitle: info.hasBreakdown
                ? Text(
                    [
                      '${tr('會員')} ${info.members}'
                          '${info.invisible > 0 ? '（${tr('隱身')} ${info.invisible}）' : ''}',
                      '${tr('訪客')} ${info.guests}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12),
                  )
                : null,
            trailing: Icon(
              _open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 18,
              color: faint(context),
            ),
            onTap: _toggle,
          ),
          if (_open) ...[
            const Divider(height: 1),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (info.users.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Text(
                  tr('論壇只對登入的會員顯示線上名單'),
                  style: TextStyle(fontSize: 12.5, color: faint(context)),
                ),
              )
            else
              ..._sections(context),
          ],
          if (info.record > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '${tr('最高紀錄')} ${info.record}'
                '${info.recordDate.isEmpty ? '' : '（${info.recordDate}）'}',
                style: TextStyle(fontSize: 11.5, color: faint(context)),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final byGroup = <String, List<OnlineUser>>{};
    for (final u in _info.users) {
      final key = _ranks.containsKey(u.group) ? u.group : 'member';
      byGroup.putIfAbsent(key, () => []).add(u);
    }
    final keys = byGroup.keys.toList()
      ..sort((a, b) => _rankOf(a).order.compareTo(_rankOf(b).order));

    final out = <Widget>[];
    for (final k in keys) {
      final rank = _rankOf(k);
      final users = byGroup[k]!;
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: rank.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                '${tr(rank.label)}  ${users.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: subtle(context),
                ),
              ),
            ],
          ),
        ),
      );
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: k == 'member' ? _names(users) : _withAvatars(users, rank.color),
        ),
      );
    }
    return out;
  }

  /// 管理團隊人少，附頭像看得出是誰
  Widget _withAvatars(List<OnlineUser> users, Color color) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final u in users)
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/u/${u.uid}'),
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: .5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: NetImage(
                    url: avatarUrl(u.uid, size: 'small'),
                    width: 22,
                    height: 22,
                    fit: BoxFit.cover,
                    placeholder: const SizedBox(width: 22, height: 22),
                    errorWidget: const SizedBox(width: 22, height: 22),
                  ),
                ),
                const SizedBox(width: 7),
                Text(u.name, style: TextStyle(fontSize: 12.5, color: color)),
              ],
            ),
          ),
        ),
    ],
  );

  /// 一般會員動輒幾百人，只排名字——幾百個頭像太重
  Widget _names(List<OnlineUser> users) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final u in users)
        ActionChip(
          label: Text(u.name, style: const TextStyle(fontSize: 12.5)),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onPressed: () => context.push('/u/${u.uid}'),
        ),
    ],
  );
}
