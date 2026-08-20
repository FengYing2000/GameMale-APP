import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 介面文字的繁→簡轉換。
///
/// App 的字串一律用繁體寫，要顯示簡體時即時轉換，
/// 這樣就不必維護兩份字串表、也不會有漏翻的問題。
class UiLang {
  UiLang._();
  static final UiLang instance = UiLang._();

  Map<String, String> _chars = const {};
  Map<String, String> _phrases = const {};
  int _maxPhrase = 0;
  bool _ready = false;

  /// 目前是否要輸出簡體
  bool simplified = false;

  Future<void> load() async {
    if (_ready) return;
    try {
      final raw = await rootBundle.loadString('assets/t2s.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _chars = (data['chars'] as Map).cast<String, String>();
      _phrases = (data['phrases'] as Map).cast<String, String>();
      for (final k in _phrases.keys) {
        if (k.length > _maxPhrase) _maxPhrase = k.length;
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  String convert(String input) {
    if (!simplified || !_ready || input.isEmpty) return input;

    final buf = StringBuffer();
    var i = 0;
    while (i < input.length) {
      var matched = false;
      final maxLen = (i + _maxPhrase > input.length) ? input.length - i : _maxPhrase;
      for (var len = maxLen; len >= 2; len--) {
        final hit = _phrases[input.substring(i, i + len)];
        if (hit != null) {
          buf.write(hit);
          i += len;
          matched = true;
          break;
        }
      }
      if (matched) continue;
      buf.write(_chars[input[i]] ?? input[i]);
      i++;
    }
    return buf.toString();
  }
}

/// 介面字串一律包這個，語言設定改變時會即時反映
String tr(String zh) => UiLang.instance.convert(zh);
