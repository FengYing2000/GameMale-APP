import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import 'package:gm_api/decor_shop.dart' as api;
import '../../../i18n/ui.dart';
import '../../../store/session.dart';
import '../../../theme.dart';
import '../../widgets/avatar.dart';
import '../../widgets/net_image.dart';
import '../../widgets/shop_kit.dart';
import '../../widgets/state_box.dart';

/// 頭銜稱號、多彩名片、背景商店：買了會顯示在自己身上的三個商店。
/// 購買／佩戴都是論壇彈窗；頭銜、背景的購買網址一打開就扣款，所以一定先確認。

Future<bool> _runShopAction(BuildContext context, api.DecorItem item, api.ShopAction a) {
  final extra = [
    if (item.price.isNotEmpty) item.price,
    if (item.duration.isNotEmpty) tr('期限 ${item.duration}'),
  ].join('，');
  return runPopup(
    context,
    a.url,
    what: a.label,
    confirmTitle: a.charges ? tr('${a.label}「${item.name}」？') : null,
    confirmMessage: a.charges ? tr('按下後會立即扣款${extra.isEmpty ? '' : '（$extra）'}，無法退款。') : '',
  );
}

List<SheetAction> _sheetActions(BuildContext context, api.DecorItem item, Future<void> Function() reload) => [
      for (final a in item.actions)
        SheetAction(
          a.label,
          () async {
            if (await _runShopAction(context, item, a) && context.mounted) {
              Navigator.of(context).maybePop();
              await reload();
            }
          },
          primary: true,
          icon: a.charges ? LucideIcons.shoppingCart : null,
        ),
    ];

// ── 頭銜稱號 ──────────────────────────────────────────

class TitleShopPage extends StatelessWidget {
  const TitleShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('頭銜稱號'),
      actions: const [WebFallbackButton('tshuz_buyname-tshuz_buyname.html')],
      tabs: [
        (tr('商店'), const _TitleTab()),
        (tr('我的稱號'), const _TitleTab(mine: true)),
      ],
    );
  }
}

class _TitleTab extends StatefulWidget {
  const _TitleTab({this.mine = false});
  final bool mine;

  @override
  State<_TitleTab> createState() => _TitleTabState();
}

class _TitleTabState extends State<_TitleTab> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    return Loader<api.DecorPage>(
      key: ValueKey(_page),
      load: () => widget.mine ? api.fetchMyTitles() : api.fetchTitleShop(page: _page),
      builder: (context, p, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          for (final n in p.notes) NoteCard(n),
          if (p.items.isEmpty) StateBox(empty: true, emptyText: p.message ?? tr(widget.mine ? '還沒有買過稱號' : '目前沒有稱號')),
          const SizedBox(height: 8),
          for (final t in p.items) _TitleRow(item: t, mine: widget.mine, reload: reload),
          ?pagerOf(p.pager, (n) => setState(() => _page = n)),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.item, required this.mine, required this.reload});
  final api.DecorItem item;
  final bool mine;
  final Future<void> Function() reload;

  @override
  Widget build(BuildContext context) {
    final t = item;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (t.image.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 40, maxWidth: 220),
                  child: NetImage(url: t.image, fit: BoxFit.contain),
                ),
              const SizedBox(height: 6),
              Text(t.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (t.price.isNotEmpty) Pill(t.price, icon: LucideIcons.coins),
                if (t.duration.isNotEmpty) Pill(t.duration, color: subtle(context), icon: LucideIcons.clock),
              ]),
              for (final (k, v) in t.info)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('$k：$v', style: TextStyle(fontSize: 12, color: faint(context))),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Column(mainAxisSize: MainAxisSize.min, children: [
            for (final a in t.actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: a.charges
                    ? FilledButton(
                        onPressed: () async {
                          if (await _runShopAction(context, t, a)) await reload();
                        },
                        child: Text(a.label),
                      )
                    : FilledButton.tonal(
                        onPressed: () async {
                          if (await _runShopAction(context, t, a)) await reload();
                        },
                        child: Text(a.label),
                      ),
              ),
          ]),
        ]),
      ),
    );
  }
}

// ── 多彩名片 ──────────────────────────────────────────

class CardShopPage extends StatelessWidget {
  const CardShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('多彩名片'),
      actions: const [WebFallbackButton('k_usercard-style.html')],
      tabs: [
        (tr('最新'), const _CardTab()),
        (tr('人氣'), const _CardTab(byHeat: true)),
        (tr('我的名片'), const _CardTab(mine: true)),
      ],
    );
  }
}

class _CardTab extends StatefulWidget {
  const _CardTab({this.byHeat = false, this.mine = false});
  final bool byHeat;
  final bool mine;

  @override
  State<_CardTab> createState() => _CardTabState();
}

class _CardTabState extends State<_CardTab> {
  int _page = 1;
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    return Loader<api.DecorPage>(
      key: ValueKey('$_page-$_nonce'),
      load: () => widget.mine ? api.fetchMyCards() : api.fetchCardShop(byHeat: widget.byHeat, page: _page),
      builder: (context, p, reload) => ItemGrid(
        maxWidth: 240,
        aspect: 1.05,
        header: [
          if (widget.mine) ...[
            for (final n in p.notes) NoteCard(n, icon: LucideIcons.idCard),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: OutlinedButton.icon(
                icon: const Icon(LucideIcons.rotateCcw, size: 17),
                label: Text(tr('恢復預設名片')),
                onPressed: () async {
                  final ok = await confirmDialog(context,
                      title: tr('恢復預設名片？'), message: tr('目前使用的名片裝扮會被取消。'), danger: true, confirm: '恢復');
                  if (!ok || !context.mounted) return;
                  if (await submitAndToast(context, api.resetUserCard)) setState(() => _nonce++);
                },
              ),
            ),
          ],
          if (p.items.isEmpty) StateBox(empty: true, emptyText: p.message ?? tr(widget.mine ? '還沒有名片' : '目前沒有名片')),
        ],
        footer: [?pagerOf(p.pager, (n) => setState(() => _page = n))],
        children: [
          for (final c in p.items)
            ItemCard(
              image: c.image,
              title: c.name,
              subtitle: [c.price, c.duration].where((e) => e.isNotEmpty).join(' / '),
              imageFit: BoxFit.cover,
              imagePadding: 0,
              corner: c.flag.isNotEmpty ? Pill(c.flag, color: okColor(context)) : null,
              badge: c.info.isEmpty ? null : Pill('${c.info.first.$1} ${c.info.first.$2}', color: subtle(context), icon: LucideIcons.flame),
              onTap: () => showItemSheet(
                context,
                title: c.name,
                tags: [
                  if (c.price.isNotEmpty) Pill(c.price, icon: LucideIcons.coins),
                  if (c.duration.isNotEmpty) Pill(c.duration, color: subtle(context), icon: LucideIcons.clock),
                ],
                rows: c.info,
                extra: _CardPreview(item: c),
                actions: _sheetActions(context, c, reload),
              ),
            ),
        ],
      ),
    );
  }
}

/// 名片預覽：背景圖上面放自己的頭像與暱稱（用名片規定的文字顏色）
class _CardPreview extends StatelessWidget {
  const _CardPreview({required this.item});
  final api.DecorItem item;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionStore>();
    final color = item.textColor == null ? Colors.white : Color(item.textColor!);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: AspectRatio(
          aspectRatio: 1.9,
          child: Stack(fit: StackFit.expand, children: [
            // 圖還沒出來時墊深色，白字名片才看得到
            const ColoredBox(color: Color(0xFF3A3F47)),
            NetImage(url: item.image, fit: BoxFit.cover),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Avatar(s.avatar, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.loggedIn ? s.name : tr('我的暱稱'),
                        style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(s.loggedIn ? 'UID ${s.uid}' : 'UID 000000', style: TextStyle(color: color.withValues(alpha: .85), fontSize: 12.5)),
                    const SizedBox(height: 8),
                    Text(tr('名片預覽'), style: TextStyle(color: color.withValues(alpha: .7), fontSize: 11.5)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── 背景商店 ──────────────────────────────────────────

class BgShopPage extends StatelessWidget {
  const BgShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('背景商店'),
      actions: const [WebFallbackButton('tshuz_bgshop-tshuz_bgshop.html')],
      tabs: [
        (tr('側欄背景'), const _BgTab(section: api.BgSection.side)),
        (tr('正文背景'), const _BgTab(section: api.BgSection.body)),
        (tr('我的背景'), const _BgTab()),
      ],
    );
  }
}

class _BgTab extends StatefulWidget {
  const _BgTab({this.section});

  /// null＝我的背景
  final api.BgSection? section;

  @override
  State<_BgTab> createState() => _BgTabState();
}

class _BgTabState extends State<_BgTab> with AutomaticKeepAliveClientMixin {
  int _cid = 0;
  int _page = 1;
  List<(String, String, int, bool)> _cats = const [];

  @override
  bool get wantKeepAlive => true;

  static int _cidOf(String url) => int.tryParse(RegExp(r'cid=(\d+)').firstMatch(url)?.group(1) ?? '') ?? 0;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final section = widget.section;
    final current = _cats.where((c) => c.$4).firstOrNull;
    return Column(children: [
      if (_cats.isNotEmpty)
        CategoryBar<int>(
          items: [for (final c in _cats) (_cidOf(c.$1), c.$2, c.$3)],
          selected: _cid != 0 || current == null ? _cid : _cidOf(current.$1),
          onSelect: (cid) => setState(() {
            _cid = cid;
            _page = 1;
          }),
        ),
      Expanded(
        child: Loader<api.DecorPage>(
          key: ValueKey('$_cid-$_page'),
          load: () => section == null ? api.fetchMyBackgrounds() : api.fetchBgShop(section, cid: _cid, page: _page),
          onData: (p) {
            if (p.categories.isNotEmpty) setState(() => _cats = p.categories);
          },
          builder: (context, p, reload) => ItemGrid(
            maxWidth: 160,
            aspect: .8,
            header: [
              if (p.items.isEmpty)
                StateBox(empty: true, emptyText: p.message ?? tr(section == null ? '還沒有買過背景' : '這個分類沒有背景')),
            ],
            footer: [
              ?pagerOf(p.pager, (n) => setState(() => _page = n)),
              if (section == null && p.notes.isNotEmpty) ...[
                SectionTitle(tr('購買紀錄')),
                for (final n in p.notes)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: Text(n, style: TextStyle(fontSize: 13, color: subtle(context))),
                  ),
              ],
            ],
            children: [
              for (final b in p.items)
                ItemCard(
                  image: b.image,
                  title: b.name,
                  subtitle: [b.price, b.duration].where((e) => e.isNotEmpty).join(' / '),
                  imageFit: BoxFit.cover,
                  imagePadding: 0,
                  onTap: () => showItemSheet(
                    context,
                    title: b.name,
                    tags: [
                      if (b.price.isNotEmpty) Pill(b.price, icon: LucideIcons.coins),
                      if (b.duration.isNotEmpty) Pill(b.duration, color: subtle(context), icon: LucideIcons.clock),
                    ],
                    rows: b.info,
                    extra: _BgPreview(url: b.image),
                    actions: _sheetActions(context, b, reload),
                  ),
                ),
            ],
          ),
        ),
      ),
    ]);
  }
}

/// 背景預覽：小圖多半是會重複鋪滿的底紋，鋪一塊給使用者看
class _BgPreview extends StatelessWidget {
  const _BgPreview({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 150,
          child: LayoutBuilder(builder: (context, c) {
            // NetImage 沒有 repeat，用格子排出鋪滿效果（論壇的底紋都是 50×50）
            const tile = 50.0;
            final cols = (c.maxWidth / tile).ceil();
            return OverflowBox(
              alignment: Alignment.topLeft,
              maxWidth: cols * tile,
              maxHeight: tile * 3,
              child: Wrap(children: [
                for (var i = 0; i < cols * 3; i++) SizedBox(width: tile, height: tile, child: NetImage(url: url, fit: BoxFit.cover)),
              ]),
            );
          }),
        ),
      ),
    );
  }
}
