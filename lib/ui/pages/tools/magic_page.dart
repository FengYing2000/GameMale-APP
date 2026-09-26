import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/magic_shop.dart' as api;
import '../../../i18n/ui.dart';
import '../../../theme.dart';
import '../../widgets/shop_kit.dart';

/// 道具超市：商店、熱銷、我的道具、記錄。購買／贈送／使用／丟棄都是論壇的彈窗表單，原生呈現
class MagicPage extends StatelessWidget {
  const MagicPage({super.key, this.initial = 0});
  final int initial;

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('道具超市'),
      initial: initial,
      actions: const [WebFallbackButton('home.php?mod=magic')],
      tabs: [
        (tr('商店'), const _ShopTab()),
        (tr('熱銷'), const _ShopTab(hot: true)),
        (tr('我的道具'), const _ShopTab(mine: true)),
        (tr('記錄'), const _LogTab()),
      ],
    );
  }
}

class _ShopTab extends StatelessWidget {
  const _ShopTab({this.mine = false, this.hot = false});
  final bool mine;
  final bool hot;

  @override
  Widget build(BuildContext context) {
    return Loader<api.MagicShopPage>(
      load: () => api.fetchMagicShop(mine: mine, hot: hot),
      builder: (context, p, reload) => ItemGrid(
        maxWidth: 150,
        aspect: .74,
        header: [
          if (p.capacity.isNotEmpty || p.balance.isNotEmpty) _Summary(page: p),
          if (p.items.isEmpty) NoteCard(p.message ?? tr(mine ? '道具包是空的' : '目前沒有道具')),
        ],
        children: [
          for (final m in p.items)
            ItemCard(
              image: m.image,
              title: m.name,
              subtitle: mine ? m.amount : m.price,
              imagePadding: 18,
              dim: m.soldOut.isNotEmpty,
              badge: m.soldOut.isNotEmpty ? Pill(m.soldOut, color: faint(context)) : null,
              onTap: () => _open(context, m, reload),
            ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, api.MagicItem m, Future<void> Function() reload) {
    return showItemSheet(
      context,
      title: m.name,
      image: m.image,
      imageHeight: 90,
      description: m.description,
      rows: [
        if (m.price.isNotEmpty) (tr('價格'), m.price),
        if (m.amount.isNotEmpty) (tr('持有'), m.amount),
      ],
      notes: [if (m.soldOut.isNotEmpty) m.soldOut],
      actions: [
        for (final (label, url) in m.actions)
          SheetAction(
            label,
            () async {
              final ok = await runPopup(context, url, what: label);
              if (ok && context.mounted) {
                Navigator.of(context).maybePop();
                await reload();
              }
            },
            primary: url.contains('operation=buy') || url.contains('operation=use'),
            danger: url.contains('operation=drop'),
            icon: switch (RegExp(r'operation=(\w+)').firstMatch(url)?.group(1)) {
              'buy' => LucideIcons.shoppingCart,
              'give' => LucideIcons.gift,
              'use' => LucideIcons.wand,
              'drop' => LucideIcons.trash2,
              _ => null,
            },
          ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.page});
  final api.MagicShopPage page;

  @override
  Widget build(BuildContext context) {
    Widget cell(IconData icon, String label, String value) => Expanded(
          child: Row(children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 11.5, color: faint(context))),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        );
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          if (page.capacity.isNotEmpty) cell(LucideIcons.package, tr('道具包容量'), page.capacity),
          if (page.balance.isNotEmpty) cell(LucideIcons.coins, tr('目前擁有'), page.balance),
        ]),
      ),
    );
  }
}

class _LogTab extends StatefulWidget {
  const _LogTab();

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> with AutomaticKeepAliveClientMixin {
  api.MagicLogKind _kind = api.MagicLogKind.use;
  int _page = 1;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(children: [
      CategoryBar<api.MagicLogKind>(
        items: [for (final k in api.MagicLogKind.values) (k, tr(k.label), null)],
        selected: _kind,
        onSelect: (k) => setState(() {
          _kind = k;
          _page = 1;
        }),
      ),
      Expanded(
        child: Loader<api.TableRows>(
          key: ValueKey('$_kind-$_page'),
          load: () => api.fetchMagicLog(_kind, page: _page),
          builder: (context, t, reload) => RecordCards(table: t, onPage: (n) => setState(() => _page = n)),
        ),
      ),
    ]);
  }
}
