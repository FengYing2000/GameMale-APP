import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/lottery.dart' as api;
import 'package:gm_api/models.dart';
import '../../../i18n/ui.dart';
import '../../../theme.dart';
import '../../widgets/net_image.dart';
import '../../widgets/shop_kit.dart';
import '../../widgets/state_box.dart';
import '../../widgets/toast.dart';

/// 日常卡片＝每日積分抽獎（it618_award）
class LotteryPage extends StatelessWidget {
  const LotteryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('日常卡片'),
      actions: const [WebFallbackButton('it618_award-award.html')],
      tabs: [
        (tr('抽卡'), const _DrawTab()),
        (tr('我的紀錄'), const _MineTab()),
      ],
    );
  }
}

class _DrawTab extends StatefulWidget {
  const _DrawTab();

  @override
  State<_DrawTab> createState() => _DrawTabState();
}

class _DrawTabState extends State<_DrawTab> {
  bool _busy = false;

  Future<void> _draw(api.LotteryInfo info, Future<void> Function() reload) async {
    final ok = await confirmDialog(
      context,
      title: tr('抽一張卡？'),
      message: info.cost.isEmpty ? '' : tr('會花費 ${info.cost}。'),
      confirm: '抽卡',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    (bool, String) r;
    try {
      r = await api.drawLottery(info.formhash);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message, kind: ToastKind.warn);
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (_) => _CardReveal(ok: r.$1, message: r.$2));
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    return Loader<api.LotteryInfo>(
      load: api.fetchLottery,
      builder: (context, info, reload) {
        final scheme = Theme.of(context).colorScheme;
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(12, 14, 12, 0),
              clipBehavior: Clip.antiAlias,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primary.withValues(alpha: .16), scheme.tertiary.withValues(alpha: .10)],
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                child: Column(children: [
                  if (info.image.isNotEmpty)
                    SizedBox(height: 110, child: NetImage(url: info.image, fit: BoxFit.contain))
                  else
                    Icon(LucideIcons.layers, size: 64, color: scheme.primary),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (info.cost.isNotEmpty) Pill(tr('每次 ${info.cost}'), icon: LucideIcons.coins),
                    if (info.perDay > 0) ...[
                      const SizedBox(width: 8),
                      Pill(tr('今天 ${info.used}/${info.perDay}'),
                          color: info.canDraw ? okColor(context) : warnColor(context), icon: LucideIcons.calendar),
                    ],
                  ]),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(LucideIcons.sparkles, size: 19),
                      label: Text(info.canDraw ? tr('抽一張') : tr('今天的次數用完了'), style: const TextStyle(fontSize: 15.5)),
                      onPressed: _busy || !info.canDraw || info.formhash.isEmpty ? null : () => _draw(info, reload),
                    ),
                  ),
                  if (info.rule.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(info.rule, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.5, color: subtle(context))),
                  ],
                ]),
              ),
            ),
            if (info.prizes.isNotEmpty) ...[
              SectionTitle(tr('卡片與獎勵')),
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(children: [
                  for (var i = 0; i < info.prizes.length; i++) ...[
                    if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      dense: true,
                      leading: _Rank(i),
                      title: Text(info.prizes[i].name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Text(info.prizes[i].reward, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Rank extends StatelessWidget {
  const _Rank(this.i);
  final int i;

  @override
  Widget build(BuildContext context) {
    const colors = [Color(0xFFE0A800), Color(0xFF9AA4B2), Color(0xFFC0773A)];
    final c = i < colors.length ? colors[i] : faint(context);
    return Container(
      width: 30,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: .15),
        border: Border.all(color: c.withValues(alpha: .6)),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Icon(LucideIcons.star, size: 14, color: c),
    );
  }
}

/// 翻牌動畫：先看到卡背，翻過來是結果
class _CardReveal extends StatelessWidget {
  const _CardReveal({required this.ok, required this.message});
  final bool ok;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 1100),
          curve: Curves.easeInOutCubic,
          builder: (context, v, _) {
            final angle = v * math.pi;
            final front = v > .5;
            return Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0012)
                ..rotateY(angle),
              child: front
                  ? Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(math.pi),
                      child: _face(context, scheme),
                    )
                  : _back(scheme),
            );
          },
        ),
        const SizedBox(height: 18),
        FilledButton.tonal(onPressed: () => Navigator.pop(context), child: Text(tr('收下'))),
      ]),
    );
  }

  Widget _back(ColorScheme scheme) => Container(
        width: 220,
        height: 310,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
          boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: .4), blurRadius: 24)],
        ),
        child: const Center(child: Icon(LucideIcons.sparkles, size: 60, color: Colors.white)),
      );

  Widget _face(BuildContext context, ColorScheme scheme) {
    final color = ok ? scheme.primary : warnColor(context);
    return Container(
      width: 220,
      height: 310,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color, width: 2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 24)],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(ok ? LucideIcons.gift : LucideIcons.circleAlert, size: 52, color: color),
        const SizedBox(height: 16),
        Text(message.isEmpty ? tr(ok ? '抽卡完成' : '抽卡失敗') : message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, height: 1.55, fontWeight: FontWeight.w600, color: scheme.onSurface)),
      ]),
    );
  }
}

class _MineTab extends StatefulWidget {
  const _MineTab();

  @override
  State<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends State<_MineTab> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    return Loader<api.LotteryMine>(
      key: ValueKey(_page),
      load: () => api.fetchLotteryMine(page: _page),
      builder: (context, m, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (m.summary.isNotEmpty)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(spacing: 8, runSpacing: 8, children: [for (final s in m.summary) Pill(s)]),
              ),
            ),
          if (m.records.isEmpty) StateBox(empty: true, emptyText: tr('還沒有抽過卡')),
          if (m.records.isNotEmpty) SectionTitle(tr('抽卡紀錄')),
          for (final r in m.records)
            ListTile(
              leading: Icon(LucideIcons.layers, color: Theme.of(context).colorScheme.primary),
              title: Text(r.prize, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(tr('花費 ${r.cost}　獎勵 ${r.reward}'), style: TextStyle(fontSize: 12.5, color: subtle(context))),
              trailing: Text(r.time, style: TextStyle(fontSize: 11.5, color: faint(context))),
            ),
          ?pagerOf(m.pager, (n) => setState(() => _page = n)),
        ],
      ),
    );
  }
}
