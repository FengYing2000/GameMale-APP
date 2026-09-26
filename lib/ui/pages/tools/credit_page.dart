import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/credit.dart' as api;
import 'package:gm_api/magic_shop.dart' show TableRows;
import '../../../i18n/ui.dart';
import '../../../theme.dart';
import '../../widgets/net_image.dart';
import '../../widgets/shop_kit.dart';
import '../../widgets/toast.dart';

/// 血液祭獻＝積分兌換：用血液換其他積分（要輸入登入密碼、有交易稅）
class CreditPage extends StatelessWidget {
  const CreditPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ToolTabs(
      title: tr('血液祭獻'),
      actions: const [WebFallbackButton('home.php?mod=spacecp&ac=credit&op=exchange')],
      tabs: [
        (tr('祭獻'), const _ExchangeTab()),
        (tr('積分記錄'), const _LogTab()),
      ],
    );
  }
}

class _ExchangeTab extends StatelessWidget {
  const _ExchangeTab();

  @override
  Widget build(BuildContext context) {
    return Loader<api.CreditExchangePage>(
      load: api.fetchCreditExchange,
      builder: (context, p, reload) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          if (p.balances.isNotEmpty) ...[
            SectionTitle(tr('我的積分')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth > 560 ? 4 : 3;
                  final w = (c.maxWidth - (cols - 1) * 8) / cols;
                  return Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final b in p.balances) SizedBox(width: w, child: _BalanceTile(balance: b)),
                  ]);
                },
              ),
            ),
          ],
          if (p.message != null)
            NoteCard(p.message!)
          else if (p.to.isEmpty || p.from.isEmpty)
            NoteCard(tr('目前沒有可以兌換的項目'))
          else
            _ExchangeForm(page: p, onDone: reload),
        ],
      ),
    );
  }
}

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.balance});
  final api.CreditBalance balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        if (balance.icon.isNotEmpty) ...[
          SizedBox(width: 18, height: 18, child: NetImage(url: balance.icon, fit: BoxFit.contain)),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(balance.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: faint(context))),
            Text(balance.value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}

class _ExchangeForm extends StatefulWidget {
  const _ExchangeForm({required this.page, required this.onDone});
  final api.CreditExchangePage page;
  final Future<void> Function() onDone;

  @override
  State<_ExchangeForm> createState() => _ExchangeFormState();
}

class _ExchangeFormState extends State<_ExchangeForm> {
  late api.CreditOption _to = widget.page.to.first;
  late api.CreditOption _from = widget.page.from.first;
  final _amount = TextEditingController(text: '1');
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPw = false;

  @override
  void dispose() {
    _amount.dispose();
    _password.dispose();
    super.dispose();
  }

  int get _n => int.tryParse(_amount.text.trim()) ?? 0;

  /// 身上還有多少來源積分（從餘額表找同名的）
  String? get _have =>
      widget.page.balances.where((b) => b.name == _from.name).firstOrNull?.value;

  Future<void> _submit() async {
    final p = widget.page;
    final cost = p.cost(_to, _from, _n);
    if (_n <= 0) return;
    if (_password.text.isEmpty) {
      toast(context, tr('請輸入登入密碼'), kind: ToastKind.warn);
      return;
    }
    final ok = await confirmDialog(
      context,
      title: tr('確定祭獻？'),
      message: tr('用 $cost ${_from.unit}${_from.name} 換 $_n ${_to.unit}${_to.name}'
          '${p.tax > 0 ? '（含 ${(p.tax * 100).toStringAsFixed(0)}% 交易稅）' : ''}。'),
      confirm: '祭獻',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final done = await submitAndToast(
      context,
      () => api.exchangeCredit(page: p, target: _to, source: _from, amount: _n, password: _password.text),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) {
      _password.clear();
      await widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.page;
    final scheme = Theme.of(context).colorScheme;
    final cost = p.cost(_to, _from, _n);
    final rate = p.cost(_to, _from, 1);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(LucideIcons.droplet, size: 18, color: scheme.error),
            const SizedBox(width: 8),
            Text(tr('祭獻換取'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 14),
          DropdownButtonFormField<api.CreditOption>(
            initialValue: _to,
            decoration: InputDecoration(labelText: tr('想換到'), border: const OutlineInputBorder()),
            items: [for (final o in p.to) DropdownMenuItem(value: o, child: Text(o.name))],
            onChanged: (v) => setState(() => _to = v ?? _to),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr('數量'),
              suffixText: _to.unit,
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (p.from.length > 1) ...[
            DropdownButtonFormField<api.CreditOption>(
              initialValue: _from,
              decoration: InputDecoration(labelText: tr('用什麼換'), border: const OutlineInputBorder()),
              items: [for (final o in p.from) DropdownMenuItem(value: o, child: Text(o.name))],
              onChanged: (v) => setState(() => _from = v ?? _from),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: tr('需要 '), style: TextStyle(color: subtle(context))),
                TextSpan(
                    text: '$cost ${_from.unit}${_from.name}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.error)),
              ])),
              const SizedBox(height: 4),
              Text(
                [
                  tr('1 ${_to.unit}${_to.name} ≈ $rate ${_from.unit}${_from.name}'),
                  if (p.tax > 0) tr('含 ${(p.tax * 100).toStringAsFixed(0)}% 交易稅'),
                  if (_have != null) tr('目前有 $_have'),
                ].join('　'),
                style: TextStyle(fontSize: 12, color: faint(context)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: !_showPw,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: tr('登入密碼'),
              helperText: tr('論壇要求輸入密碼確認，只會送到論壇'),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_showPw ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                onPressed: () => setState(() => _showPw = !_showPw),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(LucideIcons.flame, size: 18),
              label: Text(tr('祭獻')),
              onPressed: _busy || _n <= 0 ? null : _submit,
            ),
          ),
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

class _LogTabState extends State<_LogTab> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    return Loader<TableRows>(
      key: ValueKey(_page),
      load: () => api.fetchCreditLog(page: _page),
      builder: (context, t, reload) => RecordCards(table: t, onPage: (n) => setState(() => _page = n)),
    );
  }
}
