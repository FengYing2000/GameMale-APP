import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 簡體轉繁體（台灣用字）。
///
/// 資料來自 OpenCC 的 STCharacters / STPhrases / TWVariants，
/// 產生時已經把「逐字轉換就會對」的詞條剔除，只留下逐字會轉錯的，
/// 所以詞表從 49238 條縮到 9547 條。
class S2T {
  S2T._();
  static final S2T instance = S2T._();

  Map<String, String> _chars = const {};
  Map<String, String> _phrases = const {};
  int _maxPhrase = 0;
  bool _ready = false;

  bool get ready => _ready;

  Future<void> load() async {
    if (_ready) return;
    try {
      final raw = await rootBundle.loadString('assets/s2t.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _chars = (data['chars'] as Map).cast<String, String>();
      _phrases = (data['phrases'] as Map).cast<String, String>();
      for (final k in _phrases.keys) {
        if (k.length > _maxPhrase) _maxPhrase = k.length;
      }
      _ready = true;
    } catch (_) {
      // 對照表載不到就原樣顯示，不該讓整個 App 掛掉
      _ready = false;
    }
  }

  /// 先試最長的詞，比不到再退回單字
  String convert(String input) {
    if (!_ready || input.isEmpty) return input;

    final buf = StringBuffer();
    var i = 0;
    while (i < input.length) {
      var matched = false;
      final maxLen = (i + _maxPhrase > input.length) ? input.length - i : _maxPhrase;
      for (var len = maxLen; len >= 2; len--) {
        final slice = input.substring(i, i + len);
        final hit = _phrases[slice];
        if (hit != null) {
          buf.write(hit);
          i += len;
          matched = true;
          break;
        }
      }
      if (matched) continue;

      final ch = input[i];
      buf.write(_chars[ch] ?? ch);
      i++;
    }
    return buf.toString();
  }
}
