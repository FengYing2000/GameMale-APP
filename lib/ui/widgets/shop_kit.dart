import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:gm_api/http.dart' show Api;
import 'package:gm_api/magic_shop.dart' show TableRows;
import 'package:gm_api/models.dart';
import 'package:gm_api/popup.dart' as popup;
import '../../i18n/ui.dart';
import '../../theme.dart';
import 'external_link.dart';
import 'net_image.dart';
import 'pager_bar.dart';
import 'state_box.dart';
import 'toast.dart';

/// 論壇功能（勳章、道具、稱號、名片、背景…）共用的介面零件，讓十幾個頁面長得一致。

// ── 讀取 ──────────────────────────────────────────────

/// 讀一份資料：轉圈 → 內容／錯誤＋重試，可下拉重整。[builder] 拿到資料與重新讀取的函式
class Loader<T> extends StatefulWidget {
  const Loader({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.emptyText = '這裡什麼都沒有',
    this.onData,
  });

  final Future<T> Function() load;

  /// 讀到資料時通知外層（例如把分類列留在讀取畫面外面，切換分類時不會整條消失）
  final ValueChanged<T>? onData;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final bool Function(T data)? isEmpty;
  final String emptyText;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> with AutomaticKeepAliveClientMixin {
  T? _data;
  String? _err;
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = _data == null;
      _err = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() => _data = d);
      widget.onData?.call(d);
    } on DiscuzException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail(tr('讀取失敗：$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 已經有畫面時重整失敗：留著舊資料、跳提示；還沒有資料才整頁顯示錯誤
  void _fail(String message) {
    if (!mounted) return;
    if (_data != null) {
      toast(context, message, kind: ToastKind.warn);
    } else {
      setState(() => _err = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final d = _data;
    if (d == null) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(children: [
          StateBox(loading: _loading, error: _err, empty: !_loading && _err == null, onRetry: _reload),
        ]),
      );
    }
    if (widget.isEmpty?.call(d) ?? false) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(children: [StateBox(empty: true, emptyText: widget.emptyText)]),
      );
    }
    return RefreshIndicator(onRefresh: _reload, child: widget.builder(context, d, _reload));
  }
}

// ── 版面 ──────────────────────────────────────────────

/// 有分頁的功能頁
class ToolTabs extends StatelessWidget {
  const ToolTabs({super.key, required this.title, required this.tabs, this.initial = 0, this.actions = const []});

  final String title;
  final List<(String, Widget)> tabs;
  final int initial;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: tabs.length,
      initialIndex: initial.clamp(0, tabs.length - 1),
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: actions,
          bottom: tabs.length < 2
              ? null
              : TabBar(
                  isScrollable: tabs.length > 4,
                  tabAlignment: tabs.length > 4 ? TabAlignment.start : null,
                  tabs: [for (final t in tabs) Tab(text: t.$1)],
                ),
        ),
        body: tabs.length < 2 ? tabs.first.$2 : TabBarView(children: [for (final t in tabs) t.$2]),
      ),
    );
  }
}

/// 分類選擇列（橫向 chips）
class CategoryBar<T> extends StatelessWidget {
  const CategoryBar({super.key, required this.items, required this.selected, required this.onSelect});

  /// (值, 顯示文字, 數量)
  final List<(T, String, int?)> items;
  final T selected;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        children: [
          for (final (v, label, n) in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(n == null ? label : '$label  $n', style: const TextStyle(fontSize: 13)),
                selected: v == selected,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onSelect(v),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: subtle(context))),
            ),
            ?trailing,
          ],
        ),
      );
}

/// 小標籤（狀態、角標）
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: .14), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 11, color: c), const SizedBox(width: 3)],
        Flexible(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: c, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// 常用的狀態顏色
Color okColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFF7FCB6A) : const Color(0xFF2E7D32);
Color warnColor(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? const Color(0xFFF0B14A) : const Color(0xFFA35F00);
Color errColor(BuildContext c) => Theme.of(c).colorScheme.error;

/// 格狀列表用的卡片：圖＋名稱＋副標＋角標；[dim]＝買不到的淡化
class ItemCard extends StatelessWidget {
  const ItemCard({
    super.key,
    required this.image,
    required this.title,
    this.subtitle = '',
    this.badge,
    this.corner,
    this.dim = false,
    this.onTap,
    this.imageFit = BoxFit.contain,
    this.imagePadding = 10,
  });

  final String image;
  final String title;
  final String subtitle;

  /// 名稱下方的狀態標籤
  final Widget? badge;

  /// 圖右上角的標籤
  final Widget? corner;
  final bool dim;
  final VoidCallback? onTap;
  final BoxFit imageFit;
  final double imagePadding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Opacity(
      opacity: dim ? .55 : 1,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 圖吃掉文字以外的空間：卡片放進任何比例的格子都不會爆版
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: scheme.onSurface.withValues(alpha: .04),
                      child: Padding(
                        padding: EdgeInsets.all(imagePadding),
                        child: image.isEmpty
                            ? Icon(LucideIcons.image, color: faint(context))
                            : NetImage(url: image, fit: imageFit, errorWidget: Icon(LucideIcons.imageOff, color: faint(context))),
                      ),
                    ),
                    if (corner != null) Positioned(top: 6, right: 6, child: corner!),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: subtle(context))),
                    ],
                    if (badge != null) ...[const SizedBox(height: 5), badge!],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 格狀排列（手機兩～三欄，平板多一點）
class ItemGrid extends StatelessWidget {
  const ItemGrid({super.key, required this.children, this.maxWidth = 170, this.aspect = .72, this.header, this.footer});
  final List<Widget> children;
  final double maxWidth;
  final double aspect;
  final List<Widget>? header;
  final List<Widget>? footer;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (header != null) SliverList(delegate: SliverChildListDelegate(header!)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: maxWidth,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: aspect,
            ),
            delegate: SliverChildListDelegate(children),
          ),
        ),
        if (footer != null) SliverList(delegate: SliverChildListDelegate(footer!)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// 列表底下的分頁列（只有一頁就不顯示）
Widget? pagerOf(PageInfo p, ValueChanged<int> onGo) =>
    p.total > 1 || p.hasNext || p.hasPrev ? Padding(padding: const EdgeInsets.only(top: 4), child: PagerBar(pager: p, onGo: onGo)) : null;

// ── 詳細資料 ──────────────────────────────────────────

/// 詳細資料彈出單上的一顆按鈕
class SheetAction {
  const SheetAction(this.label, this.onPressed, {this.primary = false, this.danger = false, this.icon});
  final String label;
  final Future<void> Function() onPressed;
  final bool primary;
  final bool danger;
  final IconData? icon;
}

/// 商品／勳章的詳細資料：大圖、名稱、說明、資訊表、條件、按鈕
Future<void> showItemSheet(
  BuildContext context, {
  required String title,
  String image = '',
  double imageHeight = 150,
  List<Widget> tags = const [],
  String description = '',
  List<(String, String)> rows = const [],
  List<String> notes = const [],
  List<String> chips = const [],
  List<SheetAction> actions = const [],
  Widget? extra,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .88),
      child: SafeArea(
        top: false,
        child: _ItemSheet(
          title: title,
          image: image,
          imageHeight: imageHeight,
          tags: tags,
          description: description,
          rows: rows,
          notes: notes,
          chips: chips,
          actions: actions,
          extra: extra,
        ),
      ),
    ),
  );
}

class _ItemSheet extends StatefulWidget {
  const _ItemSheet({
    required this.title,
    required this.image,
    required this.imageHeight,
    required this.tags,
    required this.description,
    required this.rows,
    required this.notes,
    required this.chips,
    required this.actions,
    this.extra,
  });
  final String title;
  final String image;
  final double imageHeight;
  final List<Widget> tags;
  final String description;
  final List<(String, String)> rows;
  final List<String> notes;
  final List<String> chips;
  final List<SheetAction> actions;
  final Widget? extra;

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  String? _busy;

  Future<void> _run(SheetAction a) async {
    setState(() => _busy = a.label);
    try {
      await a.onPressed();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        if (widget.image.isNotEmpty)
          Center(
            child: SizedBox(
              height: widget.imageHeight,
              child: NetImage(url: widget.image, fit: BoxFit.contain),
            ),
          ),
        const SizedBox(height: 12),
        Text(widget.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        if (widget.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: widget.tags),
        ],
        if (widget.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(widget.description, style: TextStyle(fontSize: 14, height: 1.6, color: subtle(context))),
        ],
        if (widget.chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in widget.chips)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(c, style: TextStyle(fontSize: 12.5, color: scheme.primary)),
              ),
          ]),
        ],
        if (widget.rows.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(children: [
              for (var i = 0; i < widget.rows.length; i++) ...[
                if (i > 0) Divider(height: 1, color: Theme.of(context).dividerColor),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(widget.rows[i].$1, style: TextStyle(fontSize: 13, color: faint(context))),
                      ),
                      Expanded(
                        child: Text(widget.rows[i].$2,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
          ),
        ],
        for (final n in widget.notes) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: warnColor(context).withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(n, style: TextStyle(fontSize: 13, height: 1.5, color: warnColor(context))),
          ),
        ],
        ?widget.extra,
        if (widget.actions.isNotEmpty) ...[
          const SizedBox(height: 18),
          for (final a in widget.actions)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                height: 46,
                child: _button(a),
              ),
            ),
        ],
      ],
    );
  }

  Widget _button(SheetAction a) {
    final busy = _busy == a.label;
    final child = busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (a.icon != null) ...[Icon(a.icon, size: 17), const SizedBox(width: 6)],
            Text(a.label),
          ]);
    final onPressed = _busy != null ? null : () => _run(a);
    if (a.danger) {
      return OutlinedButton(
        style: OutlinedButton.styleFrom(foregroundColor: errColor(context)),
        onPressed: onPressed,
        child: child,
      );
    }
    return a.primary ? FilledButton(onPressed: onPressed, child: child) : FilledButton.tonal(onPressed: onPressed, child: child);
  }
}

// ── 確認與結果 ────────────────────────────────────────

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String message = '',
  String confirm = '確定',
  bool danger = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: message.isEmpty ? null : Text(message, style: const TextStyle(height: 1.55)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(tr(confirm)),
        ),
      ],
    ),
  );
  return r == true;
}

/// 送出並顯示論壇的回應。回傳是否成功
Future<bool> submitAndToast(BuildContext context, Future<SubmitResult> Function() send) async {
  try {
    final r = await send();
    if (context.mounted) toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
    return r.ok;
  } on DiscuzException catch (e) {
    if (context.mounted) toast(context, e.message, kind: ToastKind.warn);
    return false;
  }
}

/// 標題列右上角「在網頁開啟」：原生頁還沒涵蓋到的操作，還能退回論壇原本的頁面
class WebFallbackButton extends StatelessWidget {
  const WebFallbackButton(this.path, {super.key, this.title});
  final String path;
  final String? title;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tr('在網頁開啟'),
        icon: const Icon(LucideIcons.globe, size: 20),
        onPressed: () => openInApp(context, Api.desktopFullUrl(path), title: title ?? ''),
      );
}

/// 論壇彈窗的整套流程：（要扣款的先確認）→ 打開 → 是表單就原生呈現讓使用者填／確認
/// → 送出 → 顯示結果。回傳是否成功
Future<bool> runPopup(
  BuildContext context,
  String url, {
  required String what,
  String? confirmTitle,
  String confirmMessage = '',
}) async {
  if (confirmTitle != null) {
    final ok = await confirmDialog(context, title: confirmTitle, message: confirmMessage, confirm: what);
    if (!ok || !context.mounted) return false;
  }
  final popup.PopupOutcome outcome;
  try {
    outcome = await popup.openPopup(url, what: what);
  } on DiscuzException catch (e) {
    if (context.mounted) toast(context, e.message, kind: ToastKind.warn);
    return false;
  }
  if (!context.mounted) return false;
  final r = outcome.result;
  if (r != null) {
    toast(context, r.message, kind: r.ok ? ToastKind.ok : ToastKind.warn);
    return r.ok;
  }
  final result = await showModalBottomSheet<SubmitResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: _PopupFormSheet(form: outcome.form!, what: what),
    ),
  );
  if (result == null || !context.mounted) return false;
  toast(context, result.message, kind: result.ok ? ToastKind.ok : ToastKind.warn);
  return result.ok;
}

class _PopupFormSheet extends StatefulWidget {
  const _PopupFormSheet({required this.form, required this.what});
  final popup.PopupForm form;
  final String what;

  @override
  State<_PopupFormSheet> createState() => _PopupFormSheetState();
}

class _PopupFormSheetState extends State<_PopupFormSheet> {
  late final Map<String, String> _values = {for (final i in widget.form.inputs) i.name: i.value};
  final _ctrls = <String, TextEditingController>{};
  bool _busy = false;

  TextEditingController _ctrl(popup.PopupInput i) =>
      _ctrls.putIfAbsent(i.name, () => TextEditingController(text: i.value)..addListener(() => _values[i.name] = _ctrls[i.name]!.text));

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final r = await popup.submitPopup(widget.form, _values, what: widget.what);
      if (mounted) Navigator.pop(context, r);
    } on DiscuzException catch (e) {
      if (mounted) Navigator.pop(context, SubmitResult(ok: false, message: e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Text(f.title.isEmpty ? tr(widget.what) : f.title,
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final l in f.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l, style: TextStyle(fontSize: 13.5, height: 1.5, color: subtle(context))),
            ),
          for (final i in f.inputs) ...[
            const SizedBox(height: 12),
            switch (i.type) {
              'select' => DropdownButtonFormField<String>(
                  initialValue: i.options.any((o) => o.$1 == _values[i.name]) ? _values[i.name] : null,
                  decoration: InputDecoration(labelText: i.label, border: const OutlineInputBorder()),
                  items: [for (final o in i.options) DropdownMenuItem(value: o.$1, child: Text(o.$2))],
                  onChanged: (v) => setState(() => _values[i.name] = v ?? ''),
                ),
              'checkbox' => CheckboxListTile(
                  value: (_values[i.name] ?? '').isNotEmpty,
                  title: Text(i.label),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _values[i.name] = v == true ? '1' : ''),
                ),
              _ => TextField(
                  controller: _ctrl(i),
                  obscureText: i.type == 'password',
                  keyboardType: i.type == 'number' || RegExp('num|amount|数量').hasMatch(i.name + i.label)
                      ? TextInputType.number
                      : null,
                  minLines: i.type == 'textarea' ? 3 : 1,
                  maxLines: i.type == 'textarea' ? 6 : 1,
                  decoration: InputDecoration(
                    labelText: i.label.isEmpty ? null : i.label,
                    hintText: i.placeholder.isEmpty ? null : i.placeholder,
                    border: const OutlineInputBorder(),
                  ),
                ),
            },
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(f.submitLabel.isEmpty ? tr('確定') : f.submitLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// 數字輸入對話框（寄售價格、兌換數量…）。回傳 null＝取消
Future<int?> askNumber(
  BuildContext context, {
  required String title,
  String message = '',
  int? initial,
  int min = 1,
  int? max,
  String confirm = '確定',
}) async {
  final ctrl = TextEditingController(text: initial?.toString() ?? '');
  String? err;
  final r = await showDialog<int>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (message.isNotEmpty) Text(message, style: const TextStyle(height: 1.5)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              errorText: err,
              helperText: max == null ? null : tr('$min～$max'),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('取消'))),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              if (v == null || v < min || (max != null && v > max)) {
                set(() => err = tr(max == null ? '請輸入 $min 以上的數字' : '請輸入 $min～$max 的數字'));
                return;
              }
              Navigator.pop(c, v);
            },
            child: Text(tr(confirm)),
          ),
        ],
      ),
    ),
  );
  // 不在這裡 dispose：對話框的關閉動畫還在用它
  return r;
}

/// 分隔用的一小段說明卡片
class NoteCard extends StatelessWidget {
  const NoteCard(this.text, {super.key, this.icon = LucideIcons.info});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.55, color: subtle(context)))),
        ]),
      );
}

/// 記錄表格（道具記錄、積分記錄…）：手機上把每列攤成一張小卡，第一格當標題
class RecordCards extends StatelessWidget {
  const RecordCards({super.key, required this.table, this.onPage});
  final TableRows table;
  final ValueChanged<int>? onPage;

  @override
  Widget build(BuildContext context) {
    final h = table.headers;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      children: [
        if (table.rows.isEmpty) StateBox(empty: true, emptyText: tr('還沒有記錄')),
        for (final r in table.rows)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.first, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
                for (var i = 1; i < r.length; i++)
                  if (r[i].isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text.rich(
                        TextSpan(children: [
                          if (i < h.length && h[i].isNotEmpty)
                            TextSpan(text: '${h[i]}  ', style: TextStyle(color: faint(context))),
                          TextSpan(text: r[i]),
                        ]),
                        style: TextStyle(fontSize: 12.5, height: 1.45, color: subtle(context)),
                      ),
                    ),
              ]),
            ),
          ),
        if (onPage != null) ?pagerOf(table.pager, onPage!),
      ],
    );
  }
}

/// 排行名次：前三名金銀銅
class RankNumber extends StatelessWidget {
  const RankNumber(this.rank, {super.key});
  final String rank;

  static const _medals = {'1': Color(0xFFE0A800), '2': Color(0xFF9AA4B2), '3': Color(0xFFC0773A)};

  @override
  Widget build(BuildContext context) {
    final c = _medals[rank.trim()];
    return Text(
      rank,
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: c == null ? 13.5 : 16, fontWeight: FontWeight.w800, color: c ?? faint(context)),
    );
  }
}
