import 'package:html/dom.dart' as dom;

import 'discuz.dart' show submitResult, unwrapAjax;
import 'http.dart';
import 'models.dart';
import 'parse.dart';

/// 論壇的彈窗（網頁上的 showWindow）。
///
/// 外掛的「購買」「佩戴」「贈送」「申請任務」幾乎都是點了就開一個彈窗：
/// 有的彈窗是一張表單（要確認、要填收件人），有的一打開就已經做完、只回一句結果。
/// 同一個按鈕兩種都可能（例如名片購買），所以不先假設，打開之後看是哪一種：
/// * 有表單 → [PopupOutcome.form]，畫成原生表單讓使用者填、確認後 [submitPopup]
/// * 沒表單 → [PopupOutcome.result]，就是論壇回的結果
///
/// ⚠ 有些外掛的 GET 本身就會扣款（頭銜購買、背景購買、每日抽獎）。呼叫端一定要
/// **先自己跟使用者確認**再 [openPopup]，不能拿它來「預覽」。
class PopupInput {
  const PopupInput({
    required this.name,
    this.label = '',
    this.type = 'text',
    this.value = '',
    this.options = const [],
    this.placeholder = '',
  });

  final String name;

  /// 欄位旁邊的說明（表格的 th、label 文字）
  final String label;

  /// text／password／number／textarea／select／checkbox
  final String type;

  /// 預設值（checkbox 是 '1'＝勾選、''＝沒勾）
  final String value;

  /// select 的選項：(值, 顯示文字)
  final List<(String, String)> options;
  final String placeholder;
}

class PopupForm {
  const PopupForm({
    this.title = '',
    this.lines = const [],
    required this.action,
    this.hidden = const {},
    this.inputs = const [],
    this.submitName = '',
    this.submitValue = '',
    this.submitLabel = '',
  });

  /// 彈窗標題
  final String title;

  /// 說明文字（價格、餘額、注意事項…），照論壇的話一行一條
  final List<String> lines;

  /// 送出網址（相對於論壇）
  final String action;

  /// 隱藏欄位，送出時原樣帶回（formhash 等）
  final Map<String, String> hidden;

  /// 要使用者填的欄位
  final List<PopupInput> inputs;

  /// 送出鈕本身也是欄位，論壇靠它判斷是不是真的按了送出
  final String submitName;
  final String submitValue;
  final String submitLabel;
}

class PopupOutcome {
  const PopupOutcome.form(PopupForm this.form) : result = null;
  const PopupOutcome.result(SubmitResult this.result) : form = null;
  final PopupForm? form;
  final SubmitResult? result;
}

/// 打開彈窗。[what] 是這個動作的名字（「購買」「佩戴」），結果訊息用
Future<PopupOutcome> openPopup(String url, {String what = '操作'}) async {
  final path = relativePath(url);
  final sep = path.contains('?') ? '&' : '?';
  final xml = await Api.instance.get('$path${sep}infloat=yes&inajax=1', desktop: true);
  return parsePopup(unwrapAjax(xml), what: what);
}

PopupOutcome parsePopup(String html, {String what = '操作'}) {
  final doc = toDoc(html);
  final form = doc.querySelector('form');
  if (form == null) return PopupOutcome.result(submitResult(html, what));

  final hidden = <String, String>{};
  final inputs = <PopupInput>[];
  final seenRadio = <String>{};
  for (final el in form.querySelectorAll('input, select, textarea')) {
    final name = attr(el, 'name');
    if (name.isEmpty) continue;
    final tag = el.localName;
    final type = attr(el, 'type').toLowerCase();
    if (tag == 'input' && (type == 'hidden')) {
      hidden[name] = attr(el, 'value');
      continue;
    }
    if (tag == 'input' && (type == 'submit' || type == 'button' || type == 'image')) continue;
    if (tag == 'input' && type == 'radio') {
      // 同名 radio 收成一個下拉
      if (!seenRadio.add(name)) continue;
      final radios = form.querySelectorAll('input[type="radio"][name="$name"]');
      final opts = <(String, String)>[
        for (final r in radios) (attr(r, 'value'), sys(_labelOf(r))),
      ];
      final checked = radios.where((r) => r.attributes.containsKey('checked')).firstOrNull;
      inputs.add(PopupInput(
        name: name,
        label: sys(_rowLabel(el)),
        type: 'select',
        value: attr(checked ?? radios.first, 'value'),
        options: opts,
      ));
      continue;
    }
    if (tag == 'select') {
      final opts = <(String, String)>[
        for (final o in el.querySelectorAll('option')) (attr(o, 'value'), sys(txt(o))),
      ];
      final sel = el.querySelectorAll('option').where((o) => o.attributes.containsKey('selected')).firstOrNull;
      inputs.add(PopupInput(
        name: name,
        label: sys(_rowLabel(el)),
        type: 'select',
        value: sel != null ? attr(sel, 'value') : (opts.isEmpty ? '' : opts.first.$1),
        options: opts,
      ));
      continue;
    }
    if (tag == 'input' && type == 'checkbox') {
      inputs.add(PopupInput(
        name: name,
        label: sys(_labelOf(el).isNotEmpty ? _labelOf(el) : _rowLabel(el)),
        type: 'checkbox',
        value: el.attributes.containsKey('checked') ? (attr(el, 'value').isEmpty ? '1' : attr(el, 'value')) : '',
      ));
      continue;
    }
    inputs.add(PopupInput(
      name: name,
      label: sys(_rowLabel(el)),
      type: tag == 'textarea' ? 'textarea' : (type == 'password' ? 'password' : (type == 'number' ? 'number' : 'text')),
      value: tag == 'textarea' ? el.text : attr(el, 'value'),
      placeholder: sys(attr(el, 'placeholder')),
    ));
  }

  // 送出鈕：type=submit 或沒寫 type 的 button（HTML 預設就是 submit）
  dom.Element? submit;
  for (final b in form.querySelectorAll('button, input[type="submit"]')) {
    final t = attr(b, 'type').toLowerCase();
    if (b.localName == 'input' || t.isEmpty || t == 'submit') {
      submit = b;
      break;
    }
  }

  final title = txt(doc.querySelector('.flb em') ?? doc.querySelector('h3.flb') ?? doc.querySelector('h3'));
  final lines = <String>[];
  for (final el in form.querySelectorAll('p, dt, dd, li, td, th, .c > div')) {
    if (el.querySelector('input, select, textarea, button, p, dd, li, td') != null) continue;
    final t = sys(txt(el));
    if (t.isEmpty || lines.contains(t) || t == sys(title)) continue;
    if (inputs.any((i) => i.label == t)) continue;
    lines.add(t);
  }

  return PopupOutcome.form(PopupForm(
    title: sys(title),
    lines: lines,
    action: relativePath(attr(form, 'action')),
    hidden: hidden,
    inputs: inputs,
    submitName: attr(submit, 'name'),
    submitValue: attr(submit, 'value'),
    submitLabel: sys(submit == null ? '' : (submit.localName == 'input' ? attr(submit, 'value') : txt(submit))),
  ));
}

/// 送出彈窗表單。[values] 是使用者填的欄位（沒填的用預設值）
Future<SubmitResult> submitPopup(PopupForm f, Map<String, String> values,
    {String what = '操作'}) async {
  final fields = <String, String>{...f.hidden};
  for (final i in f.inputs) {
    final v = values[i.name] ?? i.value;
    // 沒勾的 checkbox 瀏覽器根本不送
    if (i.type == 'checkbox' && v.isEmpty) continue;
    fields[i.name] = v;
  }
  if (f.submitName.isNotEmpty) {
    fields[f.submitName] = f.submitValue.isEmpty ? 'true' : f.submitValue;
  }
  final target = f.action;
  final html = await Api.instance.post(
      '$target${target.contains('?') ? '&' : '?'}inajax=1', fields,
      desktop: true);
  return submitResult(unwrapAjax(html), what);
}

/// 論壇網址轉成相對路徑（去掉本站／轉發前綴與 &amp;）
String relativePath(String url) {
  var p = url.replaceAll('&amp;', '&').trim();
  if (p.startsWith(kOrigin)) p = p.substring(kOrigin.length);
  if (p.startsWith(kForumOrigin)) p = p.substring(kForumOrigin.length);
  return p.replaceFirst(RegExp(r'^/'), '');
}

/// 欄位所在那一列的標題（th 或前一格 td）
String _rowLabel(dom.Element el) {
  dom.Element? n = el;
  while (n != null && n.localName != 'tr' && n.localName != 'form') {
    n = n.parent;
  }
  if (n?.localName == 'tr') {
    final th = n!.querySelector('th');
    if (th != null) return txt(th).replaceAll('*', '').trim();
    final tds = n.querySelectorAll('td');
    if (tds.length > 1) return txt(tds.first).replaceAll('*', '').trim();
  }
  final label = _labelOf(el);
  if (label.isNotEmpty) return label;
  return attr(el, 'placeholder');
}

/// 包住欄位或 for 指向它的 label 文字
String _labelOf(dom.Element el) {
  final id = attr(el, 'id');
  if (id.isNotEmpty) {
    final root = el.parent;
    dom.Element? top = root;
    while (top?.parent != null) {
      top = top!.parent;
    }
    final l = top?.querySelector('label[for="$id"]');
    if (l != null) return txt(l);
  }
  dom.Element? n = el.parent;
  while (n != null && n.localName != 'form') {
    if (n.localName == 'label') return txt(n);
    n = n.parent;
  }
  return '';
}
