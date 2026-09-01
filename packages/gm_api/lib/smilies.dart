import 'http.dart';
import 'parse.dart';

/// 一個表情。`code` 是要插進內文的 BBCode（`{:3_41:}`）
class Smiley {
  const Smiley({required this.code, required this.url});
  final String code;
  final String url;
}

class SmileyGroup {
  const SmileyGroup({required this.name, required this.items});
  final String name;
  final List<Smiley> items;
}

/// 表情清單。手機版回覆表單只給「呆呆」那一組 24 個，
/// 完整七組在論壇自己的快取檔 `data/cache/common_smilies_var.js`（約 9 KB）。
Future<List<SmileyGroup>> fetchSmilies() async {
  if (_cache != null) return _cache!;
  final js = await Api.instance.get('data/cache/common_smilies_var.js');
  final groups = parseSmilies(js);
  if (groups.isNotEmpty) _cache = groups;
  return groups;
}

List<SmileyGroup>? _cache;

final _typeRe =
    RegExp(r"""smilies_type\['_(\d+)'\]\s*=\s*\['([^']*)',\s*'([^']*)'\]""");
final _arrayRe = RegExp(r'smilies_array\[(\d+)\]\[\d+\]\s*=\s*(\[.*?\]);',
    dotAll: true);
final _itemRe = RegExp(r"""\['(\d+)',\s*'(?:[^'\\]|\\.)*','([^']+)'""");

/// 檔案長這樣：
/// ```js
/// smilies_type['_3'] = ['呆呆', 'grapeman'];
/// smilies_array[3][1] = [['41', ':3_41:','01.gif','30','30','30'], …];
/// ```
/// 分頁（第二個索引）在 App 裡沒意義，同一組直接接起來。
List<SmileyGroup> parseSmilies(String js) {
  final names = <int, String>{};
  final folders = <int, String>{};
  for (final m in _typeRe.allMatches(js)) {
    final id = int.parse(m.group(1)!);
    names[id] = zh(m.group(2)!);
    folders[id] = m.group(3)!;
  }

  final items = <int, List<Smiley>>{};
  for (final m in _arrayRe.allMatches(js)) {
    final type = int.parse(m.group(1)!);
    final folder = folders[type];
    if (folder == null) continue;
    for (final e in _itemRe.allMatches(m.group(2)!)) {
      items.putIfAbsent(type, () => []).add(Smiley(
            code: '{:${type}_${e.group(1)}:}',
            url: absolute('static/image/smiley/$folder/${e.group(2)}'),
          ));
    }
  }

  final out = <SmileyGroup>[];
  for (final type in items.keys.toList()..sort()) {
    out.add(SmileyGroup(
      name: names[type] ?? '#$type',
      items: items[type]!,
    ));
  }
  return out;
}
