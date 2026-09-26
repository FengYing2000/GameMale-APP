import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/medal.dart' as api;
import 'package:gm_api/models.dart';
import '../../../i18n/ui.dart';
import '../../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/net_image.dart';
import '../../widgets/shop_kit.dart';
import '../../widgets/state_box.dart';
import '../../widgets/toast.dart';

/// 勳章：商城、我的勳章、榮譽、獎勵、二手市場、交易角、組合、排行
class MedalPage extends StatelessWidget {
  const MedalPage({super.key, this.initial = api.MedalTab.shop});
  final api.MedalTab initial;

  static const _order = [
    api.MedalTab.shop,
    api.MedalTab.mine,
    api.MedalTab.honor,
    api.MedalTab.reward,
    api.MedalTab.market,
    api.MedalTab.trade,
    api.MedalTab.combo,
    api.MedalTab.rank,
  ];

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('勳章'),
      initial: _order.indexOf(initial),
      tabs: [
        (tr('商城'), const _MedalListTab(tab: api.MedalTab.shop)),
        (tr('我的勳章'), const _MyMedalsTab()),
        (tr('榮譽'), const _MedalListTab(tab: api.MedalTab.honor)),
        (tr('獎勵'), const _MedalListTab(tab: api.MedalTab.reward)),
        (tr('二手市場'), const _MedalListTab(tab: api.MedalTab.market)),
        (tr('交易角'), const _TradeTab()),
        (tr('組合'), const _ComboTab()),
        (tr('排行'), const _RankTab()),
      ],
    );
  }
}

// ── 商城／榮譽／獎勵／二手市場 ─────────────────────────

class _MedalListTab extends StatefulWidget {
  const _MedalListTab({required this.tab});
  final api.MedalTab tab;

  @override
  State<_MedalListTab> createState() => _MedalListTabState();
}

class _MedalListTabState extends State<_MedalListTab> with AutomaticKeepAliveClientMixin {
  int _fid = 0;
  int _page = 1;
  int _nonce = 0;

  /// 上次讀到的分類：切換分類時分類列留著，只有下面在轉圈
  List<api.MedalCategory> _cats = const [];

  @override
  bool get wantKeepAlive => true;

  void _go({int? fid, int? page}) => setState(() {
        if (fid != null) _fid = fid;
        _page = page ?? 1;
        _nonce++;
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final current = _cats.where((c) => c.current).firstOrNull?.fid ?? _fid;
    return Column(children: [
      if (_cats.isNotEmpty)
        CategoryBar<int>(
          items: [for (final c in _cats) (c.fid, c.name, c.count)],
          selected: _fid == 0 ? current : _fid,
          onSelect: (fid) => _go(fid: fid),
        ),
      Expanded(
        child: Loader<api.MedalPage>(
          key: ValueKey('${widget.tab}-$_fid-$_page-$_nonce'),
          load: () => api.fetchMedalPage(widget.tab, fid: _fid, page: _page),
          onData: (p) {
            if (p.categories.isNotEmpty) setState(() => _cats = p.categories);
          },
          isEmpty: (p) => p.items.isEmpty && p.message == null,
          emptyText: '這裡沒有勳章',
          builder: (context, p, reload) => ItemGrid(
            header: [
              if (p.message != null && p.items.isEmpty) NoteCard(p.message!),
            ],
            footer: [
              ?pagerOf(p.pager, (n) => _go(page: n)),
              if (p.records.isNotEmpty) ...[
                SectionTitle(tr('勳章紀錄')),
                for (final r in p.records.take(12))
                  ListTile(
                    dense: true,
                    leading: Avatar(r.avatar, size: 32, onTap: r.uid == null ? null : () => context.push('/u/${r.uid}')),
                    title: Text(r.user, style: const TextStyle(fontSize: 13.5)),
                    subtitle: Text(r.text, style: TextStyle(fontSize: 12, color: faint(context))),
                  ),
              ],
            ],
            children: [
              for (final m in p.items) _medalCard(context, m, () => _openMedal(context, p, m, reload)),
            ],
          ),
        ),
      ),
    ]);
  }
}

Widget _medalCard(BuildContext context, api.MedalItem m, VoidCallback onTap) {
  final primary = m.actions.where((a) => a.kind != 'zengsong').firstOrNull;
  final owned = m.status.contains('拥有') || m.status.contains('擁有');
  Widget? badge;
  if (primary != null) {
    badge = Pill(primary.label, icon: LucideIcons.sparkles);
  } else if (m.status.isNotEmpty) {
    badge = Pill(m.status, color: owned ? okColor(context) : faint(context));
  }
  return ItemCard(
    image: m.image,
    title: m.name,
    subtitle: m.price.isNotEmpty ? m.price : m.badge,
    badge: badge,
    dim: primary == null && !owned && m.status.isNotEmpty,
    onTap: onTap,
  );
}

/// 勳章詳細資料＋按鈕
Future<void> _openMedal(BuildContext context, api.MedalPage page, api.MedalItem m, Future<void> Function() reload,
    {Widget? extra}) {
  final flags = <Widget>[
    if (m.badge.isNotEmpty) Pill(m.badge),
    if (m.status.isNotEmpty) Pill(m.status, color: warnColor(context)),
    if (m.recyclable != null) Pill(tr(m.recyclable! ? '可回收' : '不可回收'), color: m.recyclable! ? okColor(context) : faint(context)),
    if (m.renewable != null) Pill(tr(m.renewable! ? '可續期' : '不可續期'), color: m.renewable! ? okColor(context) : faint(context)),
    if (m.consignable != null) Pill(tr(m.consignable! ? '可寄售' : '不可寄售'), color: m.consignable! ? okColor(context) : faint(context)),
  ];

  return showItemSheet(
    context,
    title: m.name,
    image: m.image,
    tags: flags,
    description: m.description,
    rows: m.info,
    notes: [if (m.condition.isNotEmpty) m.condition],
    chips: m.effects,
    extra: extra,
    actions: [
      for (final a in m.actions)
        SheetAction(
          _actionLabel(a),
          () => _runMedalAction(context, page, m, a, reload),
          primary: a.kind == 'goumai' || a.kind == 'goumaijishou' || a.kind == 'lingqu' || a.kind == 'UPLV',
          danger: a.kind == 'huishou',
        ),
    ],
  );
}

String _actionLabel(api.MedalAction a) => switch (a.kind) {
      'goumai' || 'goumaijishou' => a.arg.isEmpty ? tr('購買') : '${tr('購買')}（${a.arg}）',
      'huishou' => a.arg.isEmpty ? tr('回收') : '${tr('回收')}（${tr('得')} ${a.arg}）',
      'UPLV' => a.arg.isEmpty ? tr('升級') : '${tr('升級')}（${a.arg}）',
      'jishou' => tr('寄售'),
      'xuqi' => tr('續期'),
      'lingqu' => tr('領取'),
      'zengsong' => tr('贈送'),
      _ => a.label,
    };

Future<void> _runMedalAction(BuildContext context, api.MedalPage page, api.MedalItem m, api.MedalAction a,
    Future<void> Function() reload) async {
  if (a.kind == 'zengsong') {
    final ok = await _gift(context, page, m);
    if (ok && context.mounted) Navigator.of(context).maybePop();
    return;
  }

  int? price;
  if (a.kind == 'jishou') {
    final max = int.tryParse(a.arg);
    price = await askNumber(
      context,
      title: tr('寄售 ${m.name}'),
      message: tr('設定售價（最多 ${a.arg}）。會收取寄售中介費。'),
      initial: max,
      max: max,
      confirm: '寄售',
    );
    if (price == null) return;
  } else {
    final (title, msg) = switch (a.kind) {
      'goumai' || 'goumaijishou' => (tr('購買 ${m.name}？'), a.arg.isEmpty ? '' : tr('需要 ${a.arg}')),
      'huishou' => (tr('回收 ${m.name}？'), tr('回收後這枚勳章就沒了${a.arg.isEmpty ? '' : '，可得 ${a.arg}'}。')),
      'UPLV' => (tr('升級 ${m.name}？'), a.arg.isEmpty ? '' : tr('升級需要消耗 ${a.arg}')),
      'xuqi' => (tr('續期 ${m.name}？'), a.arg),
      'lingqu' => (tr('領取 ${m.name}？'), ''),
      _ => (tr('確定？'), ''),
    };
    final ok = await confirmDialog(context, title: title, message: msg, danger: a.kind == 'huishou');
    if (!ok || !context.mounted) return;
  }

  if (!context.mounted) return;
  final ok = await submitAndToast(context, () => api.medalAction(page, a, price: price));
  if (ok && context.mounted) {
    Navigator.of(context).maybePop();
    await reload();
  }
}

/// 贈送：先驗 UID（顯示對方暱稱）→ 附言 → 確認
Future<bool> _gift(BuildContext context, api.MedalPage page, api.MedalItem m) async {
  final uidCtrl = TextEditingController();
  final msgCtrl = TextEditingController();
  String? name;
  String? err;
  var checking = false;
  final go = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(tr('贈送 ${m.name}')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: uidCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('對方 UID'),
              border: const OutlineInputBorder(),
              errorText: err,
              helperText: name == null ? null : tr('對方：$name'),
              suffixIcon: checking
                  ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(
                      icon: const Icon(LucideIcons.search),
                      onPressed: () async {
                        final uid = int.tryParse(uidCtrl.text.trim());
                        if (uid == null || uid <= 0) return set(() => err = tr('UID 不正確'));
                        set(() => checking = true);
                        final n = await api.verifyMedalGiftUid(uid, page.formhash).catchError((_) => null);
                        set(() {
                          checking = false;
                          name = n;
                          err = n == null ? tr('找不到這個 UID') : null;
                        });
                      },
                    ),
            ),
            onChanged: (_) => set(() => name = null),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: msgCtrl,
            maxLines: 3,
            decoration: InputDecoration(labelText: tr('附言（可不填）'), border: const OutlineInputBorder()),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(onPressed: name == null ? null : () => Navigator.pop(c, true), child: Text(tr('贈送'))),
        ],
      ),
    ),
  );
  final uid = int.tryParse(uidCtrl.text.trim());
  final text = msgCtrl.text.trim();
  if (go != true || uid == null || !context.mounted) return false;
  return submitAndToast(
      context, () => api.giftMedal(medalId: m.id, uid: uid, message: text, formhash: page.formhash));
}

// ── 我的勳章 ──────────────────────────────────────────

class _MyMedalsTab extends StatefulWidget {
  const _MyMedalsTab();

  @override
  State<_MyMedalsTab> createState() => _MyMedalsTabState();
}

class _MyMedalsTabState extends State<_MyMedalsTab> {
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Loader<api.MedalPage>(
      key: ValueKey(_nonce),
      load: () => api.fetchMedalPage(api.MedalTab.mine),
      isEmpty: (p) => p.items.isEmpty && p.stats.isEmpty,
      emptyText: '還沒有勳章',
      builder: (context, p, reload) {
        final scheme = Theme.of(context).colorScheme;
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (p.stats.isNotEmpty)
              SliverToBoxAdapter(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('持有統計'), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: subtle(context))),
                      const SizedBox(height: 8),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final s in p.stats)
                          SizedBox(
                            width: (MediaQuery.sizeOf(context).width - 24 - 28 - 10) / 2,
                            child: _StatBar(stat: s),
                          ),
                      ]),
                    ]),
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: OutlinedButton.icon(
                  icon: const Icon(LucideIcons.arrowUpDown, size: 17),
                  label: Text(tr('調整顯示順序')),
                  onPressed: () async {
                    final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => _ReorderPage(page: p)));
                    if (saved == true) setState(() => _nonce++);
                  },
                ),
              ),
            ),
            for (final g in p.groups) ...[
              SliverToBoxAdapter(child: SectionTitle('${g.title}  ${g.items.length}')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 130,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: .7,
                  ),
                  delegate: SliverChildListDelegate([
                    for (final m in g.items)
                      ItemCard(
                        image: m.image,
                        title: m.name,
                        subtitle: m.badge,
                        corner: m.shown == false
                            ? Icon(LucideIcons.eyeOff, size: 15, color: faint(context))
                            : null,
                        badge: m.actions.any((a) => a.kind == 'UPLV')
                            ? Pill(tr('可升級'), color: scheme.primary, icon: LucideIcons.arrowUp)
                            : null,
                        onTap: () => _openMedal(context, p, m, reload, extra: _ShownSwitch(medal: m)),
                      ),
                  ]),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        );
      },
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({required this.stat});
  final api.MedalStat stat;

  @override
  Widget build(BuildContext context) {
    final limit = int.tryParse(stat.limit);
    final v = limit == null || limit == 0 ? null : (stat.owned / limit).clamp(0.0, 1.0);
    final color = stat.full ? warnColor(context) : Theme.of(context).colorScheme.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(stat.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
        Text('${stat.owned}/${stat.limit}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: v ?? (stat.owned > 0 ? 1 : 0), minHeight: 5, color: color),
      ),
    ]);
  }
}

/// 「在帖子裡顯示」開關（網頁那個勾勾）
class _ShownSwitch extends StatefulWidget {
  const _ShownSwitch({required this.medal});
  final api.MedalItem medal;

  @override
  State<_ShownSwitch> createState() => _ShownSwitchState();
}

class _ShownSwitchState extends State<_ShownSwitch> {
  late bool _on = widget.medal.shown ?? true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.medal.userMedalId;
    if (widget.medal.shown == null || id == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(tr('在帖子裡顯示')),
        subtitle: Text(tr('關掉後別人看不到這枚勳章'), style: TextStyle(fontSize: 12, color: faint(context))),
        value: _on,
        onChanged: _busy
            ? null
            : (v) async {
                setState(() {
                  _on = v;
                  _busy = true;
                });
                try {
                  await api.setMedalShown(id, v);
                } on DiscuzException catch (e) {
                  if (context.mounted) toast(context, e.message, kind: ToastKind.warn);
                  if (mounted) setState(() => _on = !v);
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
      ),
    );
  }
}

/// 拖曳調整勳章順序（網頁是拖拉 .myblok，送出全部我的勳章編號）
class _ReorderPage extends StatefulWidget {
  const _ReorderPage({required this.page});
  final api.MedalPage page;

  @override
  State<_ReorderPage> createState() => _ReorderPageState();
}

class _ReorderPageState extends State<_ReorderPage> {
  late final List<api.MedalItem> _items = [
    for (final m in widget.page.items)
      if (m.userMedalId != null) m,
  ];
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await api.setMedalOrder([for (final m in _items) m.userMedalId!]);
      if (!mounted) return;
      toast(context, tr('已儲存順序'), kind: ToastKind.ok);
      Navigator.pop(context, true);
    } on DiscuzException catch (e) {
      if (mounted) toast(context, e.message, kind: ToastKind.warn);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('調整顯示順序')),
        actions: [
          TextButton(onPressed: _busy ? null : _save, child: Text(tr('儲存'))),
        ],
      ),
      body: ReorderableListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        onReorderItem: (from, to) => setState(() => _items.insert(to, _items.removeAt(from))),
        itemBuilder: (context, i) {
          final m = _items[i];
          return ListTile(
            key: ValueKey(m.userMedalId),
            leading: SizedBox(width: 40, height: 40, child: NetImage(url: m.image, fit: BoxFit.contain)),
            title: Text(m.name),
            subtitle: m.badge.isEmpty ? null : Text(m.badge, style: TextStyle(fontSize: 12, color: faint(context))),
            trailing: const Icon(LucideIcons.gripVertical),
          );
        },
      ),
    );
  }
}

// ── 交易角 ────────────────────────────────────────────

class _TradeTab extends StatefulWidget {
  const _TradeTab();

  @override
  State<_TradeTab> createState() => _TradeTabState();
}

class _TradeTabState extends State<_TradeTab> {
  int _page = 1;
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Loader<api.TradePage>(
      key: ValueKey('$_page-$_nonce'),
      load: () => api.fetchTradePage(page: _page),
      builder: (context, t, reload) => ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (t.notice.isNotEmpty) NoteCard(t.notice),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: FilledButton.icon(
              icon: const Icon(LucideIcons.arrowLeftRight, size: 18),
              label: Text(tr('發布交易單')),
              onPressed: () async {
                final done = await Navigator.of(context)
                    .push<bool>(MaterialPageRoute(builder: (_) => _TradeCreatePage(trade: t)));
                if (done == true) setState(() => _nonce++);
              },
            ),
          ),
          SectionTitle(tr('正在等待的交易單')),
          if (t.orders.isEmpty) StateBox(empty: true, emptyText: tr('目前沒有交易單')),
          for (final o in t.orders) _TradeCard(order: o, onDone: () => setState(() => _nonce++)),
          ?pagerOf(t.pager, (n) => setState(() => _page = n)),
        ],
      ),
    );
  }
}

class _TradeCard extends StatelessWidget {
  const _TradeCard({required this.order, required this.onDone});
  final api.TradeOrder order;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final o = order;
    Widget side(String label, List<(String, String)> medals) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12, color: faint(context))),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (name, img) in medals)
                Tooltip(
                  message: name,
                  child: SizedBox(
                    width: 64,
                    child: Column(children: [
                      SizedBox(height: 44, child: NetImage(url: img, fit: BoxFit.contain)),
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
                ),
            ]),
          ]),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(o.avatar, size: 30, onTap: o.uid == null ? null : () => context.push('/u/${o.uid}')),
            const SizedBox(width: 8),
            Expanded(
              child: Text(o.user, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text('${o.no}  ${o.time}', style: TextStyle(fontSize: 12, color: faint(context))),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            side(tr('對方提供'), o.offer),
            Padding(
              padding: const EdgeInsets.only(top: 26, left: 6, right: 6),
              child: Icon(LucideIcons.arrowLeftRight, size: 18, color: faint(context)),
            ),
            side(tr('對方想要'), o.want),
          ]),
          if (o.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(o.note, style: TextStyle(fontSize: 12.5, color: warnColor(context))),
          ],
          if (o.form != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final f = o.form!;
                  final ok = await confirmDialog(context,
                      title: f.label.isEmpty ? tr('確認交易？') : '${f.label}？',
                      message: f.confirm.isEmpty ? tr('系統會立即交換雙方列出的全部勳章，不能撤銷。') : f.confirm);
                  if (!ok || !context.mounted) return;
                  if (await submitAndToast(context, () => api.submitTradeForm(f))) onDone();
                },
                child: Text(o.form!.label.isEmpty ? tr('確認交易') : o.form!.label),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// 發布交易單：選我提供的（最多 4）、我想要的（最多 4）、可指定對象
class _TradeCreatePage extends StatefulWidget {
  const _TradeCreatePage({required this.trade});
  final api.TradePage trade;

  @override
  State<_TradeCreatePage> createState() => _TradeCreatePageState();
}

class _TradeCreatePageState extends State<_TradeCreatePage> {
  final _offer = <int>{};
  final _want = <int>{};
  final _target = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final t = widget.trade;
    final uid = int.tryParse(_target.text.trim());
    final ok = await confirmDialog(
      context,
      title: tr('發布交易單？'),
      message: tr('發布後會立即扣除${t.fee.isEmpty ? '發布費' : ' ${t.fee}'}，取消也不退還。'
          '${uid != null ? '\n這張單只給 UID $uid，其他人只能看、不能成交。' : ''}'),
      confirm: '發布',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await submitAndToast(
        context,
        () => api.createTrade(
            formhash: t.formhash, offer: _offer.toList(), want: _want.toList(), targetUid: uid));
    if (mounted) setState(() => _busy = false);
    if (done && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trade;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('發布交易單')),
          bottom: TabBar(tabs: [
            Tab(text: '${tr('我提供')} ${_offer.length}/${t.maxOffer}'),
            Tab(text: '${tr('我想要')} ${_want.length}/${t.maxWant}'),
          ]),
        ),
        body: TabBarView(children: [
          _MedalPicker(medals: t.myMedals, categories: t.categories, picked: _offer, max: t.maxOffer, onChanged: () => setState(() {})),
          _MedalPicker(medals: t.allMedals, categories: t.categories, picked: _want, max: t.maxWant, onChanged: () => setState(() {})),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('指定接收 UID（留空＝公開）'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  onPressed: _busy || _offer.isEmpty || _want.isEmpty ? null : _submit,
                  child: Text(t.fee.isEmpty ? tr('發布') : '${tr('發布')}（${t.fee}）'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MedalPicker extends StatefulWidget {
  const _MedalPicker({required this.medals, required this.categories, required this.picked, required this.max, required this.onChanged});
  final List<api.TradeMedal> medals;
  final List<(String, String)> categories;
  final Set<int> picked;
  final int max;
  final VoidCallback onChanged;

  @override
  State<_MedalPicker> createState() => _MedalPickerState();
}

class _MedalPickerState extends State<_MedalPicker> with AutomaticKeepAliveClientMixin {
  String _cat = '';
  String _q = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = [
      for (final m in widget.medals)
        if ((_cat.isEmpty || m.category == _cat) && (_q.isEmpty || m.name.contains(_q))) m,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: TextField(
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            hintText: tr('搜尋勳章'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
      ),
      CategoryBar<String>(
        items: [('', tr('全部'), null), for (final c in widget.categories) (c.$1, c.$2, null)],
        selected: _cat,
        onSelect: (v) => setState(() => _cat = v),
      ),
      Expanded(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 110,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: .78,
          ),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final m = list[i];
            final on = widget.picked.contains(m.id);
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (on) {
                  widget.picked.remove(m.id);
                } else if (widget.picked.length >= widget.max) {
                  toast(context, tr('最多選 ${widget.max} 個'), kind: ToastKind.warn);
                  return;
                } else {
                  widget.picked.add(m.id);
                }
                setState(() {});
                widget.onChanged();
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: on ? scheme.primary : Theme.of(context).dividerColor, width: on ? 2 : 1),
                  color: on ? scheme.primary.withValues(alpha: .08) : null,
                ),
                padding: const EdgeInsets.all(6),
                child: Column(children: [
                  Expanded(child: NetImage(url: m.image, fit: BoxFit.contain)),
                  const SizedBox(height: 4),
                  Text(m.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ── 組合 ──────────────────────────────────────────────

class _ComboTab extends StatelessWidget {
  const _ComboTab();

  @override
  Widget build(BuildContext context) {
    return Loader<api.MedalComboPage>(
      load: api.fetchMedalCombos,
      isEmpty: (c) => c.combos.isEmpty,
      builder: (context, c, reload) {
        final active = [for (final x in c.combos) if (x.active) x];
        final rest = [for (final x in c.combos) if (!x.active) x];
        return ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.summary, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  if (c.bonuses.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final (need, bonus, chance) in c.bonuses) Pill('$need $bonus · $chance', color: okColor(context)),
                    ]),
                  ],
                ]),
              ),
            ),
            if (active.isNotEmpty) SectionTitle(tr('已激活')),
            for (final x in active) _ComboCard(combo: x),
            if (rest.isNotEmpty) SectionTitle(tr('尚未激活')),
            for (final x in rest) _ComboCard(combo: x),
          ],
        );
      },
    );
  }
}

class _ComboCard extends StatelessWidget {
  const _ComboCard({required this.combo});
  final api.MedalCombo combo;

  @override
  Widget build(BuildContext context) {
    final x = combo;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(x.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Pill(x.status, color: x.active ? okColor(context) : warnColor(context)),
          ]),
          if (x.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(x.description, style: TextStyle(fontSize: 12.5, color: subtle(context))),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (name, img, owned) in x.medals)
              Tooltip(
                message: name,
                child: Opacity(
                  opacity: owned ? 1 : .35,
                  child: Stack(clipBehavior: Clip.none, children: [
                    SizedBox(width: 44, height: 44, child: NetImage(url: img, fit: BoxFit.contain)),
                    if (owned)
                      Positioned(right: -4, bottom: -4, child: Icon(LucideIcons.circleCheck, size: 15, color: okColor(context))),
                  ]),
                ),
              ),
          ]),
          if (x.effects.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in x.effects) Text('· $e', style: TextStyle(fontSize: 12.5, color: subtle(context))),
          ],
        ]),
      ),
    );
  }
}

// ── 排行 ──────────────────────────────────────────────

class _RankTab extends StatelessWidget {
  const _RankTab();

  @override
  Widget build(BuildContext context) {
    return Loader<List<api.MedalRankSection>>(
      load: api.fetchMedalRank,
      isEmpty: (s) => s.isEmpty,
      builder: (context, sections, reload) => ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          for (final s in sections) ...[
            SectionTitle(s.title),
            for (final r in s.rows)
              ListTile(
                leading: SizedBox(
                  width: 70,
                  child: Row(children: [
                    SizedBox(width: 28, child: RankNumber(r.rank)),
                    const SizedBox(width: 6),
                    Avatar(r.avatar, size: 34),
                  ]),
                ),
                title: Text(r.user),
                subtitle: r.reward.isEmpty || r.reward == '无' || r.reward == '無'
                    ? null
                    : Text('${tr('每日獎勵')}：${r.reward}', style: TextStyle(fontSize: 12, color: faint(context))),
                trailing: Text(r.count, style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: r.uid == null ? null : () => context.push('/u/${r.uid}'),
              ),
          ],
        ],
      ),
    );
  }
}
